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

/////////////////////
////////////////////////
public func JSONObjectWithData(fromData data: Data) -> Any? {
	return try? JSONSerialization.jsonObject(with: data, options: [])
}

public enum RestApiFlags {
	case emptyBody
}

public protocol RestApi:Tagged {
	associatedtype In:Encodable
	var input:In {get}
	var view:UIView? {get}
	var debugLevel:APIDebugLevel {get}
	var url:String {get}
	var method:Alamofire.HTTPMethod {get}
	var encoding:Alamofire.ParameterEncoding {get}
	var flags:Set<RestApiFlags> {get}
	var activityHandlerStyle:UIActivityIndicatorViewStyle {get}
}

public extension RestApi {
	var view:UIView? {return nil}
	var debugLevel:APIDebugLevel {return .verbose}
	var flags:Set<RestApiFlags> {return Set<RestApiFlags>()}
	var logTags:[String] {return ["api",Self.tag]}
	var activityHandlerStyle:UIActivityIndicatorViewStyle {return .gray}
	var encoding:Alamofire.ParameterEncoding {
		if method==HTTPMethod.get {
			return URLEncoding(destination: .methodDependent)
		} else {
			return JSONEncoding()
		}
	}
}
public protocol ObjApi:RestApi {
	associatedtype Out:Creatable
}
public protocol ArrayApi:RestApi {
	associatedtype Out:Arrayable
}
extension RestApi {
	func makeRequest(debugCallId:Int)->(Result<DataRequest>,UIProgressView?)
	{

		var jsonDict:[String : ApiParam]?=nil
		if !flags.contains(.emptyBody) && method != HTTPMethod.get {
			guard let dict=input.encode().JSONObject() as? [String:Any] else {
				return (.failure(NSError(domain: "no dictionary in request", code: 0, userInfo: nil)),nil)
			}
			jsonDict=dict.typeConstrain()
		}
		let req=MunicipiumAPIAlamofire
			.request(url, method: method, parameters: jsonDict, encoding: encoding, headers: nil)
			.debugLog(debugCallId:debugCallId, debugLevel:debugLevel,logTags:logTags, params:jsonDict)
		let success = Result<DataRequest>.success(req)
		var progressView:UIProgressView?=nil
		if let v=self.view, success.isSuccess {
			progressView=UIProgressView(progressViewStyle: .default)
			progressView?.tintColor = .purple
			onMain{
				v.addSubview(progressView!)
				constrain(progressView!) {
					let sv=$0.superview!
					$0.top == sv.top
					$0.trailing == sv.trailing
					$0.leading == sv.leading
				}
				progressView!.setContentCompressionResistancePriority(1000, for: UILayoutConstraintAxis.vertical)
			}
			req.downloadProgress { (progress) in
				progressView!.setProgress(
					Float(progress.fractionCompleted),
					animated: true)
			}
		}
		
		return (success,progressView)
	}
}
public extension ObjApi {
	
	func rxObject()->Observable<Out>
	{
		let debugCallId=nextCallId
		nextCallId+=1
		
		return Observable.create{ (observer) -> Disposable in
			let start=Date()
			let (request,progressView)=self.makeRequest(debugCallId:debugCallId)
			guard let req=request.value else {
				observer.onError(request.error!)
				return Disposables.create()
			}

			req.responseJSON { response in
				defer {
					progressView?.removeFromSuperview()
					log("[\(debugCallId)]call duration: \(Date().timeIntervalSince(start))",self.logTags,.verbose)
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
		}
	}
}
public extension ArrayApi {
	func rxArray()->Observable<[Out]>
	{
		let debugCallId=nextCallId
		nextCallId+=1
		
		return Observable.create{ (observer) -> Disposable in
			let start=Date()
			let (request,progressView)=self.makeRequest(debugCallId:debugCallId)
			guard let req=request.value else {
				observer.onError(request.error!)
				return Disposables.create()
			}
			
			req.responseJSON { response in
				defer {
					progressView?.removeFromSuperview()
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
		}
	}
}
public protocol Creatable:Decodable {
	static func create(fromData:Data)->Self?
	static func decodeMe(_:Any)->Decoded<Self>
}
public protocol Arrayable:Decodable {
	static func createArray(fromData:Data)->[Self]?
	static func decodeMeArray(_:[Any])->Decoded<[Self]>
}
public extension Creatable {
	static func create(fromData data: Data) -> Self? {
		let j=(try? JSONSerialization.jsonObject(with: data, options: [])) ?? [String:ApiParam]()
		
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
	
}
open class RestApiBase<_In,_Out> {
	public typealias In = _In
	public typealias Out = _Out
	public let input:In
	public let view:UIView?
	public init(input:In, view:UIView?) {
		self.input=input
		self.view=view
	}
	// default argument not working... (crash the compiler)
	public init(input:In) {
		self.input=input
		self.view=nil
	}
}
