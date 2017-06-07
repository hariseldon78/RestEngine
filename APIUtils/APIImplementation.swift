//
//  APIImplementation.swift
//  Municipium
//
//  Created by Roberto Previdi on 28/10/15.
//  Copyright © 2015 Slowmedia. All rights reserved.
//

import Foundation
import UIKit
import ObjectMapper
import RxSwift
import Alamofire
import AlamofireObjectMapper
import Cartography
import DataVisualization
import M13ProgressSuite
import Reachability

let RetryCountOnError=3
let WaitBeforeRetry=0.3
public let APICallsQueue:OperationQueue={
	let opQ=OperationQueue()
	opQ.qualityOfService = .userInitiated
	return opQ
}()
public var randomNetworkLatencies=false
public var simulateNoConnection=false
public let APIScheduler=OperationQueueScheduler(operationQueue: APICallsQueue)
let globalDisposeBag=DisposeBag()
public let globalLog=LogManager()
public let rxReachability=Variable<Reachability.NetworkStatus>(.notReachable)
public let reachability:Reachability=Reachability(hostname:"http://municipiumapp.it")!
var _showConnectionToast:((Bool)->())?
public func initReachabilityNotifier(showConnectionToast:@escaping (Bool)->())
{
	_showConnectionToast=showConnectionToast
	NotificationCenter.default.rx.notification(ReachabilityChangedNotification)
		.subscribe(onNext:{notif in
		guard let reachability=notif.object as? Reachability else {return}
		rxReachability.value=reachability.currentReachabilityStatus
	}).addDisposableTo(globalDisposeBag)
	try! reachability.startNotifier()
	rxReachability.asObservable()
		.skip(1)
		.map{$0.online}
		.distinctUntilChanged()
		.subscribe(onNext: { (status) in
			_showConnectionToast?(status)
		})
		.addDisposableTo(globalDisposeBag)
}


public extension Reachability.NetworkStatus {
	public var online:Bool { return self != .notReachable }
}

public func log(_ message:String,_ tags:[String]) {
	globalLog.log(message,tags)
}

public func log(_ message:String,_ level:LogLevel) {
	globalLog.log(message,level)
}

public func log(_ message:String,tags:[String]=[String](),level:LogLevel = .debug) {
	globalLog.log(message,tags,level)
}
public func log(_ message:String,_ tag:String,_ level:LogLevel = .debug) {
	globalLog.log(message,[tag],level)
}

public func log(_ message:String,_ tags:[String],_ level:LogLevel) {
	globalLog.log(message,tags,level)
}
struct StringStream :TextOutputStream {
	mutating func write(_ string: String) {
		output=string
	}
	var output:String=""
}
public func logDump<T>(_ obj:T,name:String?,_ tags:[String],_ level:LogLevel)
{
	var ss=String()
	if let name=name {
		dump(obj,to:&ss,name:name)
	}else{
		dump(obj,to:&ss)
	}
	globalLog.log(ss,tags,level)
}
public func logDump<T>(_ obj:T,name:String?,_ tag:String,_ level:LogLevel) {
	logDump(obj, name: name, [tag], level)
}

func concatArray<T>(_ a:Array<T>,_ b:Array<T>)->Array<T> {
	var c=a
	c.append(contentsOf: b)
	return c
}
func +<T>(a:Array<T>,b:Array<T>)->Array<T> {
	return concatArray(a, b)
}

public struct ApiNetworkRequest:Mappable {
	public var method=""
	public var tag=""
	public var baseUrl=""
	public var params=[(String,ApiParam)]() {
		didSet {
			params=params.sorted { $0.0 < $1.0 }
		}
	}
	var paramsString:String {
		return params.map { $0.0+"="+String(describing: $0.1) }.joined(separator:"&")
	}
	public init?(map:Map) {}
	public init(tag:String,baseUrl:String,params:[String:ApiParam]?,method:Alamofire.HTTPMethod) {
		self.tag=tag
		self.method=method.rawValue
		self.baseUrl=baseUrl
		self.params=(params ?? [String:ApiParam]()).sorted { $0.0 < $1.0 }
	}
	public mutating func mapping(map:Map) {
		method 	<- map["method"]
		tag 	<- map["tag"]
		baseUrl	<- map["baseUrl"]
		var ps=paramsString
		ps 		<- map["params"]
	}
}

public let apiCache=Cache<ApiNetworkRequest,CachableBase>(name:"apiCache")

let MunicipiumAPIAlamofire={ ()->Alamofire.SessionManager in
	let policies:[String:ServerTrustPolicy]=[
		"www.municipiumstaging.it": .disableEvaluation,
		"www.municipiumdemo.it": .disableEvaluation
	]
	
	let manager=Alamofire.SessionManager(serverTrustPolicyManager:ServerTrustPolicyManager(policies:policies))
	
	return manager
	
}()

public typealias APIDebugLevel=LogLevel

let DefaultAPIDebugLevel=APIDebugLevel.verbose
enum InterpretData{
	case json(s:String)
	case data(s:String)
	case empty
	
	init(data:Data?){
		guard let data=data else {self = .empty; return}
		if let json=(try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
			).flatMap({
				try? JSONSerialization.data(withJSONObject: $0, options: .prettyPrinted)
			}).flatMap({
				String(data: $0, encoding: String.Encoding.utf8)
			}) {
			self = .json(s:json)
		}else{
			self = .data(s:String(data:data,encoding:.utf8) ?? "(not utf8)")
		}
	}
	func toString()->String{
		switch self {
		case let .json(s):
			return "(json)\n\(s)"
		case let .data(s):
			return "(data) \(s)"
		case .empty:
			return "(no data)"
		}
	}
}

public extension String {
	func onlyBorders(length:Int,tolerance:Int)->String {
		if characters.count>length+tolerance {
			let start=substring(to: index(startIndex, offsetBy: length/2))
			let end=substring(from: index(endIndex, offsetBy: -(length/2)))
			return "\(start) [...] \(end)"
		} else {
			return self
		}
	}
	
}

func debug<T>(debugCallId:Int,response:DataResponse<T>,debugLevel:APIDebugLevel,logTags:[String])
{
	log("[\(debugCallId)] \(response)",logTags+["api"],.info)
	
	if debugLevel.atLeast(.verbose)
	{
		log("[\(debugCallId)] response data:\(InterpretData(data:response.data).toString().onlyBorders(length:800,tolerance:50))",logTags+["api"],debugLevel)
	}
	
}
public extension Alamofire.Request
{
	
	public func debugLog(debugCallId:Int,debugLevel:APIDebugLevel,logTags:[String],params:[String:ApiParam]?) -> Self
	{
		log("[\(debugCallId)] Alamofire.Request: \(self)",logTags+["api"],.debug)
		if debugLevel.atLeast(.verbose) {
			log("[\(debugCallId)] Alamofire.Request.HTTPBody: \(InterpretData(data:self.request?.httpBody).toString().onlyBorders(length:800,tolerance:50))",logTags+["api"],.verbose)
		}
		if let params=params
		{
			let pars="\(params)".onlyBorders(length:800,tolerance:50)
			log("[\(debugCallId)] params:\(pars)",logTags+["api"],.debug)
		}
		return self
	}
}


struct Timestamp: CustomStringConvertible {
	let t=Date()
	var description: String {return t.description}
}

public var nextCallId=0
func _obsImplementation<T>(
	debugCallId: Int,
	method:Alamofire.HTTPMethod,
	url:String,
	params:[String:ApiParam]?,
	progress:APIProgress?,
	debugLevel:APIDebugLevel,
	logTags:[String],
	encoding:ParameterEncoding,
	f:@escaping (_ req:Alamofire.DataRequest,_ observer:AnyObserver<T>,_ runMeAtEnd:@escaping ()->())->())->Observable<T>
{
	
	return Observable.create{ (observer) -> Disposable in
		var upStart,downStart : Date?
		var done=false
		let actInd=UIApplication.shared.activityHandler(style: UIActivityIndicatorViewStyle.white)
		let start=Date()
		delay(0.5){
				guard let progress=progress, !done else {return}
				progress.start()
				log("[\(debugCallId)] \(Timestamp()) showProgress: \(progress)",logTags+["api"],.verbose)
			}
		var req:Alamofire.DataRequest!
		if encoding is JSONEncoding {
			
			let jsonData=try! JSONSerialization.data(withJSONObject: params ?? [:], options: .prettyPrinted)
			req=MunicipiumAPIAlamofire
				.upload(jsonData, to: url, method: method, headers: ["Content-type":"application/json"])
				.uploadProgress(closure: { (prog) in
					if upStart==nil {upStart=Date()}
					progress?.setCompletion(progress:prog,start:upStart!)
			})
		} else {
			req=MunicipiumAPIAlamofire
				.request(url, method:method, parameters:params, encoding:encoding, headers:nil)
		}

		req=req.debugLog(debugCallId:debugCallId, debugLevel:debugLevel,logTags:logTags, params:params)
			.downloadProgress { (prog) in
				if downStart==nil {downStart=Date()}
				progress?.setCompletion(progress:prog,start:downStart!)
		}

		let atEnd={ () -> () in
			log("[\(debugCallId)]call duration: \(Date().timeIntervalSince(start))",logTags+["api"],.verbose)
			actInd.hide()
			done=true
			guard let progress=progress else {return}
			progress.finish()
			log("[\(debugCallId)] \(Timestamp()) finishProgress: \(progress)",logTags+["api"],.verbose)
		}
		let callBack={
			f(req, observer,atEnd)
		}
		if simulateNoConnection {
			observer.on(.error(NSError(domain: "No connection (SIMULATION)", code: 0, userInfo: nil)))
			atEnd()
		} else if randomNetworkLatencies {
			delay(5.0*Double(arc4random()) / Double(UINT32_MAX)){ onMain(callBack) }
		} else {
			onMain(callBack)
		}
		
		return Disposables.create {
			guard !done else {return}
			done=true
			actInd.hide()
			req.cancel()
			guard let progress=progress else {return}
			progress.cancel()
			log("[\(debugCallId)] \(Timestamp()) cancelProgress: \(progress)",logTags+["api"],.verbose)
		}
		}.retryWhen { (errors: Observable<NSError>) in
			return errors.scan(0) { ( a, e) in
				log("[\(debugCallId)]received error: \(e.localizedDescription)",logTags+["api"])
				log("[\(debugCallId)]errors count: \(a+1)",logTags+["api"])
				let b=a+1
				if b >= RetryCountOnError {
					throw e
				}
				progress?.setIndeterminate()
				Thread.sleep(forTimeInterval: WaitBeforeRetry)
				return b
			}
	}
	
}


func createObjObservable<T>(_ params:[String:ApiParam]?,progress:APIProgress?,debugLevel:APIDebugLevel,logTags:[String])->Observable<T> where T:ObjectWithUrl, T:Mappable
{
	let debugCallId=nextCallId
	nextCallId+=1 // not thread safe, but it's only for debugging purpose so no worries
	return _obsImplementation(debugCallId: debugCallId, method:T.method, url: T.url(params), params: params, progress:progress, debugLevel: debugLevel,logTags:logTags, encoding:T.encoding) { (req, observer, runMeAtEnd) -> () in
		req.responseObject{ (response:DataResponse<T>) -> Void in
			debug(debugCallId: debugCallId, response: response,debugLevel: debugLevel,logTags:logTags)
			var needComplete=false
			switch response.result
			{
			case .success(let obj) where obj.prepareFluent(params).isValid():
				logDump(obj,name:"[\(debugCallId)]obj",logTags+["api"],.debug)
				
				observer.on(.next(obj))
				needComplete=true

			case .success(let obj): // risposta leggibile ma non "valid": il server ha dato un errore.
				observer.on(.error(NSError(domain: "Invalid response", code: -1, userInfo: ["obj":obj])))
			case .failure(let error): // significa che l'object mapping non ha funzionato
				observer.on(.error(error))
//			default:
//				observer.on(.error(NSError(domain: "Invalid response", code: -1, userInfo: response.result)))
				
			}
			runMeAtEnd()
			if needComplete {
				observer.on(.completed)
			}
		}
	}
}
func createArrayObservableWithItemResult<T>(_ params:[String:ApiParam]?,progress:APIProgress?,debugLevel:APIDebugLevel,logTags:[String])->Observable<T> where T:ObjectWithArrayUrl, T:Mappable
{
	let debugCallId=nextCallId
	nextCallId+=1 // not thread safe, but it's only for debugging purpose so no worries
	return _obsImplementation(debugCallId: debugCallId, method:T.method, url: T.arrayUrl(params), params: params, progress:progress, debugLevel: debugLevel,logTags:logTags,encoding:T.encoding) { (req, observer, runMeAtEnd) -> () in
		req.responseArray{ (response:DataResponse<[T]>) -> Void in
			debug(debugCallId: debugCallId, response: response,debugLevel: debugLevel,logTags:logTags)
			switch response.result
			{
			case .success(let array):
				logDump(array,name:"[\(debugCallId)]array",logTags+["api"],.debug)
				array.filter {
					$0.isValid()
					}.forEach {
						observer.on(.next($0))
				}
				observer.on(.completed)
			case .failure(let error):
				observer.on(.error(error))
			}
			runMeAtEnd()
		}

	}
}

func createArrayObservableWithArrayResult<T>(_ params:[String:ApiParam]?,progress:APIProgress?,debugLevel:APIDebugLevel,logTags:[String])->Observable<[T]> where T:ObjectWithArrayUrl, T:Mappable
{
	let debugCallId=nextCallId
	nextCallId+=1 // not thread safe, but it's only for debugging purpose so no worries
	return _obsImplementation(debugCallId: debugCallId, method:T.method, url: T.arrayUrl(params), params: params, progress:progress, debugLevel: debugLevel,logTags:logTags,encoding:T.encoding) { (req, observer, runMeAtEnd) -> () in
		req.responseArray{ (response:DataResponse<[T]>) -> Void in
			debug(debugCallId:debugCallId, response:response, debugLevel:debugLevel,logTags:logTags)
			switch response.result
			{
			case .success(let array):
				logDump(array,name:"[\(debugCallId)]array",logTags+["api"],.debug)
				observer.on(.next(
					array.filter {
						$0.isValid()
					})
				)
				observer.on(.completed)
			case .failure(let error):
				observer.on(.error(error))
			}
			runMeAtEnd()
		}
		
	}
}

