//
//  RestEngine.swift
//  Municipium
//
//  Created by Roberto Previdi on 17/01/17.
//  Copyright © 2017 municipiumapp. All rights reserved.
//

import Foundation
import Argo
import Ogra
import Alamofire
import Curry
import Runes
import RxSwift
import Cartography
import DataVisualization

/////////////////////
////////////////////////
public enum Cachability {
	case never
	case cache(expiry:Expiry)
}

public class CachableCreatable<T>:CachableBase where T:Creatable {
	public required init?(coder aDecoder: NSCoder) {
		cacheDate=aDecoder.decodeObject(forKey: "date") as! Date?
		if let s=aDecoder.decodeObject(forKey: "obj") as? String,
			let data=s.data(using: String.Encoding.utf8),
			let JSON = JSONObjectWithData(fromData: data),
			let tmp=T.create(fromJSON:JSON)
		{
			obj=tmp
			super.init(coder: aDecoder)
			return
		}
		return nil
	}
	
	open override func encode(with aCoder: NSCoder) {
		cacheDate=timeSource.now()
		aCoder.encode(cacheDate,forKey:"date")
		guard let data=try? JSONSerialization.data(
			withJSONObject: obj.encode().JSONObject(),
			options: []),
			let json = String(data:data,encoding: .utf8)
			else {
				aCoder.encode(nil,forKey:"obj")
				return
		}
		aCoder.encode(json,forKey:"obj")
	}
	
	open var obj:T
	open var cacheDate:Date?
	init(obj:T)
	{
		self.obj=obj
		super.init()
	}
}

public class CachableArrayable<T>:CachableBase where T:Arrayable {
	public required init?(coder aDecoder: NSCoder) {
		cacheDate=aDecoder.decodeObject(forKey: "date") as! Date?
		if let data=aDecoder.decodeObject(forKey: "obj") as? [String]
		{
			let jsons=data.map{
				return (try? JSONSerialization.jsonObject(
					with: $0.data(using: .utf8)!,
					options: [])) ?? [String:ApiParam]()
			}
			if let obj=T.createArray(fromJSON:jsons) {
				self.obj=obj
				super.init(coder: aDecoder)
				return
			}
		}
		return nil
	}
	
	open override func encode(with aCoder: NSCoder) {
		cacheDate=timeSource.now()
		aCoder.encode(cacheDate,forKey:"date")
		let jsons:[String]=obj
			.map{
				$0.encode().JSONObject()
			}
			.map{
				try? JSONSerialization.data(withJSONObject: $0, options: [])
			}
			.filter{$0 != nil}
			.map{$0!}
			.map{
				String(data:$0,encoding: .utf8)
			}
			.filter{$0 != nil}
			.map{$0!}
		
		
		aCoder.encode(jsons,forKey:"obj")
	}
	
	open var obj:[T]
	open var cacheDate:Date?
	init(obj:[T])
	{
		self.obj=obj
		super.init()
	}
}


public let restApiCache=Cache<ApiNetworkRequest,CachableBase>(name:"restApiCache")
public func JSONObjectWithData(fromData data: Data) -> Any? {
	return try? JSONSerialization.jsonObject(with: data, options: [])
}

public enum RestApiFlags {
	case emptyBody
}

public protocol RestApi:Tagged {
	associatedtype In:Encodable
	var input:In {get}
	var progress:APIProgress? {get}
	var debugLevel:APIDebugLevel {get}
	var url:String {get}
	var method:Alamofire.HTTPMethod {get}
	var encoding:Alamofire.ParameterEncoding {get}
	var flags:Set<RestApiFlags> {get}
	var cachability:Cachability {get}
}

public extension RestApi {
	var progress:APIProgress? {return nil}
	var debugLevel:APIDebugLevel {return .verbose}
	var flags:Set<RestApiFlags> {return Set<RestApiFlags>()}
	var logTags:[String] {return ["api",Self.tag]}
	var encoding:Alamofire.ParameterEncoding {
		if method==HTTPMethod.get {
			return URLEncoding(destination: .methodDependent)
		} else {
			return JSONEncoding()
		}
	}
	var cachability:Cachability {return .never}

}
public protocol ObjApi:RestApi {
	associatedtype Out:Creatable
}
public protocol ArrayApi:RestApi {
	associatedtype Out:Arrayable
}
extension RestApi {
	
	func cacheKey()->ApiNetworkRequest
	{
		var jsonDict:[String : ApiParam]?=nil
		if !flags.contains(.emptyBody) && method != HTTPMethod.get {
			if let dict=input.encode().JSONObject() as? [String:Any]{
				jsonDict=dict.typeConstrain()
			}
		}
		return ApiNetworkRequest(tag: Self.tag, baseUrl: self.url, params: jsonDict, method:self.method)
	}
	func makeRequest(debugCallId:Int)->Result<DataRequest>
	{
		var upStart,downStart : Date?
		var jsonDict:[String : ApiParam]?=nil
		if !flags.contains(.emptyBody) && method != HTTPMethod.get {
			guard let dict=input.encode().JSONObject() as? [String:Any] else {
				return .failure(NSError(domain: "no dictionary in request", code: 0, userInfo: nil))
			}
			jsonDict=dict.typeConstrain()
		}
		
		var req:Alamofire.DataRequest!
		if encoding is JSONEncoding {
			
			let jsonData=try! JSONSerialization.data(withJSONObject: jsonDict ?? [:], options: .prettyPrinted)
			req=MunicipiumAPIAlamofire
				.upload(jsonData, to: url, method: method, headers: ["Content-type":"application/json"])
				.uploadProgress(closure: { (progress) in
					if upStart==nil {upStart=Date()}
					self.progress?.setCompletion(progress:progress,start:upStart!)
				})
		} else {
			req=MunicipiumAPIAlamofire
				.request(url, method:method, parameters:jsonDict, encoding:encoding, headers:nil)
		}
		
		req=req.debugLog(debugCallId:debugCallId, debugLevel:debugLevel,logTags:logTags, params:jsonDict)
			.downloadProgress { (progress) in
				if downStart==nil {downStart=Date()}
				self.progress?.setCompletion(progress:progress,start:downStart!)
		}
		let success = Result<DataRequest>.success(req)
		
		return success
	}
}
public extension ObjApi {
	
	func rxObject()->Observable<Out>
	{
		let debugCallId=nextCallId
		nextCallId+=1
		
		let output=PriorityObservable<Out>()

		var cacheAge:CacheAge?
		switch self.cachability {
		case .cache(let expiry):
			_=0
			if let old=restApiCache.get(cacheKey()) as? CachableCreatable<Out>,let date=old.cacheDate {
				cacheAge=expiry.age(cachingDate: date)
				if !(cacheAge == .expired && rxReachability.value.online) {
					output.onNext(prio:0,value:old.obj)
				}
			}
		case .never:
			_=0
		}
		
		if rxReachability.value.online && cacheAge != .fresh {
			Observable<Out>.create{ (observer) -> Disposable in
				let start=Date()
				let actInd=UIApplication.shared.activityHandler(style: UIActivityIndicatorViewStyle.white)
				var done=false
				delay(0.5) {
					if !done {
						self.progress?.start()
					}
				}
				let request=self.makeRequest(debugCallId:debugCallId)
				guard let req=request.value else {
					observer.onError(request.error!)
					return Disposables.create()
				}
				
				req.responseJSON { response in
					defer {
						log("[\(debugCallId)]call duration: \(Date().timeIntervalSince(start))",self.logTags,.verbose)
						actInd.hide()
						done=true
						self.progress?.finish()
					}
					guard let j = response.result.value else {
						observer.onError(NSError(domain: "Invalid json: \(response.result.value)", code: 0, userInfo: nil))
						return
					}
					log("[\(debugCallId)]Response: \(j)",self.logTags,.verbose)
					let decoded:Decoded<Out> = Out.decodeMe(j)
					switch decoded
					{
					case .success(let obj):
						observer.onNext(obj)
						observer.onCompleted()
						
					case .failure(let decodingError):
						observer.onError(decodingError)
					}
					
				}
				return Disposables.create {
					guard !done else {return}
					done=true
					actInd.hide()
					req.cancel()
					self.progress?.cancel()
				}
				}.retryWhen { (errors: Observable<NSError>) in
					return errors.scan(0) { ( a, e) in
						log("[\(debugCallId)]received error: \(e.localizedDescription)",self.logTags)
						log("[\(debugCallId)]errors count: \(a+1)",self.logTags)
						let b=a+1
						if b >= RetryCountOnError {
							throw e
						}
						Thread.sleep(forTimeInterval: WaitBeforeRetry)
						return b
					}
				}.subscribe(
					onNext: { (obj) in
						switch self.cachability{
						case .cache(_):
							restApiCache.set(CachableCreatable<Out>(obj: obj),forKey: self.cacheKey())
						case .never:
							_=0
						}
						output.onNext(prio: 1, value: obj)
				},
					onError: { (e) in
						output.onError(error: e)
				},
					onCompleted: {
						output.onCompleted()
				})
				.addDisposableTo(globalDisposeBag)
		} else if !rxReachability.value.online {
			_showConnectionToast?(false)
		}
		return output.asObservable()
	}
}
public extension ArrayApi {
	func rxArray()->Observable<[Out]>
	{
		let debugCallId=nextCallId
		nextCallId+=1
		
		let output=PriorityObservable<[Out]>()
		
		var cacheAge:CacheAge?
		switch self.cachability {
		case .cache(let expiry):
			_=0
			if let old=restApiCache.get(cacheKey()) as? CachableArrayable<Out>, let date=old.cacheDate {
				cacheAge=expiry.age(cachingDate: date)
				if !(cacheAge == .expired && rxReachability.value.online) {
					output.onNext(prio:0,value:old.obj)
				}
			}
		case .never:
			_=0
		}
		if rxReachability.value.online && cacheAge != .fresh {
			Observable<[Out]>.create{ (observer) -> Disposable in
				let start=Date()
				let request=self.makeRequest(debugCallId:debugCallId)
				guard let req=request.value else {
					observer.onError(request.error!)
					return Disposables.create()
				}
				
				req.responseJSON { response in
					defer {
						log("[\(debugCallId)]call duration: \(Date().timeIntervalSince(start))",self.logTags,.verbose)
					}
					log("timeline: \(response.timeline)",self.logTags,.verbose)
					var json:[Any]!
					switch response.result {
					case .failure(let e):
						observer.onError(e)
						return
					case .success(let j):
						guard let jArray = j as? [Any] else {
							observer.onError(NSError(domain: "Invalid json: \(response.result.value)", code: 0, userInfo: nil))
							return
						}
						json=jArray
					}
					
					log("[\(debugCallId)]Response \(json)",self.logTags,.verbose)
					let decoded:Decoded<[Out]> = Out.decodeMeArray(json)
					switch decoded
					{
					case .success(let array):
						observer.onNext(array)
						observer.onCompleted()
						
					case .failure(let decodingError):
						observer.onError(decodingError)
					}
				}
				return Disposables.create {
					req.cancel()
				}
				}.retryWhen { (errors: Observable<NSError>) in
					return errors.scan(0) { ( a, e) in
						log("[\(debugCallId)]received error: \(e.localizedDescription)",self.logTags)
						log("[\(debugCallId)]errors count: \(a+1)",self.logTags)
						let b=a+1
						if b >= RetryCountOnError {
							throw e
						}
						Thread.sleep(forTimeInterval: WaitBeforeRetry)
						return b
					}
				}.subscribe(
					onNext: { (obj) in
						switch self.cachability{
						case .cache(_):
							restApiCache.set(CachableArrayable<Out>(obj: obj),forKey: self.cacheKey())
						case .never:
							_=0
						}
						output.onNext(prio: 1, value: obj)
				},
					onError: { (e) in
						output.onError(error: e)
				},
					onCompleted: {
						output.onCompleted()
				}).addDisposableTo(globalDisposeBag)
		} else if !rxReachability.value.online {
			_showConnectionToast?(false)
		}
		return output.asObservable()
	}
}
public protocol Creatable:Decodable,Encodable {
	static func create(fromData:Data)->Self?
	static func create(fromJSON:Any)->Self?
	static func decodeMe(_:Any)->Decoded<Self>
	
}
public protocol Arrayable:Decodable,Encodable {
	static func createArray(fromData:Data)->[Self]?
	static func createArray(fromJSON:[Any])->[Self]?
	static func decodeMeArray(_:[Any])->Decoded<[Self]>
}
public extension Creatable {
	static func create(fromData data: Data) -> Self? {
		let j=(try? JSONSerialization.jsonObject(with: data, options: [])) ?? [String:ApiParam]()
		return create(fromJSON: j)
	}
	static func create(fromJSON j:Any)->Self? {
		let ado:Decoded<Self> = Self.decodeMe(j)
		switch ado {
		case let .success(x): return x
		default: return nil
		}
	}
	// DON'T WORK IN PROTOCOL... IMPLEMENT IN CONCRETE CLASSES
	//	static func decodeMe(_ j:Any) -> Decoded<Self> {
	//		return Argo.decode(j)
	//	}
}
public extension Arrayable {
	static func createArray(fromData data: Data) -> [Self]? {
		let jArray=(try? JSONSerialization.jsonObject(with: data, options: [])).flatMap {
			$0 as? [Any]
			} ?? [Any]()
		return createArray(fromJSON:jArray)
	}
	static func createArray(fromJSON jArray:[Any]) -> [Self]? {
		let ado:Decoded<[Self]> = Self.decodeMeArray(jArray)
		switch ado {
		case let .success(x): return x
		default: return nil
		}
	}
	// DON'T WORK IN PROTOCOL... IMPLEMENT IN CONCRETE CLASSES
	//	static func decodeMeArray(_ j:[Any]) -> Decoded<[Self]> {
	//		return Argo.decode(j)
	//	}
	
}
public struct EmptyIn:Encodable {
	public init() {}
	public func encode()->JSON {
		return JSON.object([:])
	}
}


public struct EmptyOut:Creatable {
	public static func decode(_ j: JSON) -> Decoded<EmptyOut> {
		return .success(EmptyOut())
	}
	public static func decodeMe(_ j:Any) -> Decoded<EmptyOut> {
		return .success(EmptyOut())
	}
	public init(){}
	public func encode() -> JSON {
		return JSON.object([:])
	}
	
}
open class RestApiBase<_In,_Out> {
	public typealias In = _In
	public typealias Out = _Out
	public let input:In
	public let progress:APIProgress?
	public init(input:In, progress:APIProgress?) {
		self.input=input
		self.progress=progress
	}
	// default argument not working... (crash the compiler)
	public init(input:In) {
		self.input=input
		self.progress=nil
	}
}
