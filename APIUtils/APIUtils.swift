//
//  APIUtils.swift
//  Municipium
//
//  Created by Roberto Previdi on 07/10/15.
//  Copyright © 2015 Slowmedia. All rights reserved.
//

import Foundation
import ObjectMapper
import RxSwift
import Alamofire
import AlamofireObjectMapper
//import PromiseKit
import DataVisualization
import SwiftDate


let API_SHARE_REPLAY_BUFFER=100

func assertMain() {
		assert(OperationQueue.current == OperationQueue.main)
}
//
func assertBackground() {
	#if DEBUG
		assert(OperationQueue.current != OperationQueue.main)
	#endif
}
//
//func ==(lhs:NSDate,rhs:NSDate)->Bool
//{
//	return lhs.isEqualToDate(rhs)
//}
//func <(lhs:Date,rhs:Date)->Bool
//{
//	return (lhs as NSDate).earlierDate(rhs)==lhs
//}

public protocol ApiParam {}
extension Bool: ApiParam {}
extension String: ApiParam {}
extension Int: ApiParam {}
extension Double: ApiParam {}
extension NSNumber: ApiParam {}
extension Dictionary: ApiParam {}
extension Array: ApiParam {}



enum APIError: Error
{
	case incorrectParameters
}
extension String
{
	init<T:Mappable>(_ obj:T)
	{
		self=Mapper<T>().toJSONString(obj,prettyPrint:true)!
	}
}
public protocol APIObject:Validable
{
	static var method:Alamofire.HTTPMethod {get}
	static var encoding:Alamofire.ParameterEncoding {get}
}
public extension APIObject
{
//	static var encoding:Alamofire.ParameterEncoding { return URLEncoding(destination: .methodDependent)}
	static var encoding:Alamofire.ParameterEncoding {
		if Self.method==Alamofire.HTTPMethod.get {
			return URLEncoding(destination: .methodDependent)
		} else {
			return JSONEncoding()
		}
	}
}
public protocol APIble
{
	// Serve ad evitare una circular reference...
	// static func API()
}
public protocol ObjectWithUrl:APIObject
{
	static func url(_ params: [String:ApiParam]?) ->String
	func prepare(_ params:[String:ApiParam]?)
}
public extension ObjectWithUrl
{
	func prepare(_ params:[String:ApiParam]?) {}
	func prepareFluent(_ params:[String:ApiParam]?) -> Self {
		prepare(params)
		return self
	}
}
public protocol ObjectWithArrayUrl:APIObject
{
	static func arrayUrl(_ params: [String:ApiParam]?) ->String
}

public func ==<T:Mappable>(lhs: T, rhs: T) -> Bool
{
	return Mapper<T>().toJSONString(lhs,prettyPrint:false)==Mapper<T>().toJSONString(rhs,prettyPrint:false)
}

func clone<T:Mappable>(_ obj:T)->T?
{
	if let json=Mapper<T>().toJSONString(obj,prettyPrint:false)
	{
		return Mapper<T>().map(JSONString: json)
	}
	else
	{
		return nil
	}
}

//// TESTABLE TIMESOURCE
protocol TimeSource {
	func now()->Date
}
struct DefaultTimeSource:TimeSource{
	static var _instance=DefaultTimeSource()
	static var instance:DefaultTimeSource { return _instance }
	func now()->Date
	{
		return Date()
	}
}
var timeSource:TimeSource=DefaultTimeSource.instance


extension Date {
	func nextWithTime(hour:Int,minute:Int,second:Int) throws ->Date
	{
		let d=try self.atTime(hour: hour, minute: minute, second: second)
		if d>self {
			return d
		} else {
			return try self.startOfDay.add(components: [.day:1]).atTime(hour: hour, minute: minute, second: second)
		}
	}
}
public indirect enum Expiry {
	case hours(Double)
	case minutes(Double)
	case always
	case everyDayAt(h:Int,m:Int)
	case earliest(exp0:Expiry,exp1:Expiry)
	
	func isExpired(cachingDate:Date) -> Bool
	{
		switch self {
		case .hours(let h):
			return timeSource.now().addingTimeInterval(-3600.0*h) >= cachingDate
		case .minutes(let m):
			return timeSource.now().addingTimeInterval(-60*m) >= cachingDate
		case .always:
			return true
		case .everyDayAt(let h, let m):
			let exp=try! cachingDate.nextWithTime(hour:h,minute:m,second:0)
			return timeSource.now()>exp
		case .earliest(let exp0, let exp1):
			return exp0.isExpired(cachingDate: cachingDate) ||
				exp1.isExpired(cachingDate: cachingDate)
		}
	}
	
	func isFresh(cachingDate:Date) -> Bool
	{
		return self.updatePriority(cachingDate: cachingDate)<0.05
	}
	func age(cachingDate:Date) -> CacheAge
	{
		if isExpired(cachingDate: cachingDate) {
			return .expired
		} else if isFresh(cachingDate: cachingDate) {
			return .fresh
		} else {
			return .old
		}
	}
	func updatePriority(cachingDate:Date)->Double {
		switch self {
		case .hours(let h):
			let age=fabs(cachingDate.timeIntervalSince(timeSource.now()))/3600
			return age/h
		case .minutes(let m):
			let age=fabs(cachingDate.timeIntervalSince(timeSource.now()))/60
			return age/m
		case .always:
			return 1.0
		case .everyDayAt(let h, let m):
			let now=timeSource.now()
			let exp=try! cachingDate.nextWithTime(hour:h,minute:m,second:0)
			if now>=exp {
				return 1.0
			}
			let difference=(now-exp)/3600.0
			return 1.0-difference/24.0
		case .earliest(let exp0, let exp1):
			return max(exp0.updatePriority(cachingDate: cachingDate),
				exp1.updatePriority(cachingDate: cachingDate))
		}
	}
	
}

public protocol Expirable
{
	static var expiry:Expiry {get}
}
extension Alamofire.HTTPMethod:CustomStringConvertible
{
	public var description: String
	{
		return self.rawValue
	}
}
public protocol Tagged {
	static var tag:String {get}
	var logTags:[String] {get}
}

public extension Tagged {
	static var tag:String { return String(describing:type(of: self)) }
	var logTags:[String] {return [Self.tag]}
}

public protocol APISubject: Mappable,Expirable,Tagged {
	static var mandatoryParams:[String] {get}
	static var automaticParams:[String:ApiParam]? {get}
	func invalidateCache()
}


public extension APISubject
{
	static var mandatoryParams:[String] {return []}
	func invalidateCache()
	{
		let _=apiCache.invalidate { $0.tag==Self.tag }
	}
}
public protocol APIResult: Mappable,Tagged {
	associatedtype SubjectType//:Mappable//APISubject,APIble
	static var mapper:(_ obj:inout SubjectType,_ map:Map)->() {get}
	
}
public protocol CachableEntity
{
	associatedtype OutputType
	static func key(_ params:[String:ApiParam]?)->ApiNetworkRequest
	var cacheDate:Date? {get}
	var obj:OutputType {get}
}
open class CachableBase:NSObject,NSCoding {
	public override init() {}
	required public init?(coder aDecoder: NSCoder) {
		super.init()
	}
	open func encode(with aCoder: NSCoder) {}
}
func + <K, V> (left: [K:V], right: [K:V]) -> [K:V] {
	var out=left
	for (k, v) in right {
		out.updateValue(v, forKey: k)
	}
	return out
}
func + <K, V> (left: [K:V], right: [K:V]?) -> [K:V] {
	guard let right=right else { return left }
	return left+right
}
open class CachableObject<T> : CachableBase,CachableEntity where T:APISubject, T:ObjectWithUrl {
	public typealias OutputType=T
	required public init?(coder aDecoder: NSCoder)
	{
		cacheDate=aDecoder.decodeObject(forKey: "date") as! Date?
		if let data=aDecoder.decodeObject(forKey: "obj") as? String,
			let JSON = Mapper<T>.parseJSONStringIntoDictionary(JSONString: data) {
			let map = Map(mappingType: .fromJSON, JSON: JSON, toObject: true, context: nil)
			if let _=T(map:map) {
				obj=Mapper<T>().map(JSONString:data)!
				super.init(coder:aDecoder)
				return
			}
		}
		return nil
	}
	open class func key(_ params:[String:ApiParam]?)->ApiNetworkRequest
	{
		return ApiNetworkRequest(
			tag: T.tag,
			baseUrl: T.url(params),
			params: (params ?? [String:ApiParam]())+T.automaticParams)
	}
	open var obj:T
	open var cacheDate:Date?
	open override func encode(with aCoder: NSCoder) {
		cacheDate=timeSource.now()
		aCoder.encode(cacheDate,forKey:"date")
		guard let json=Mapper<T>().toJSONString(obj, prettyPrint: false) else {
			aCoder.encode(nil,forKey:"obj")
			return
		}
		if DefaultAPIDebugLevel.atLeast(.debug) {
			log("encoded json: \(json)",["api","cache",T.tag])
		}
		aCoder.encode(json,forKey:"obj")
	}
	init(obj:T)
	{
		self.obj=obj
		super.init()
	}
}

open class CachableArray<T> : CachableBase,CachableEntity where T:APISubject, T:ObjectWithArrayUrl{
	public typealias OutputType=[T]
	required public init?(coder aDecoder: NSCoder)
	{
		super.init(coder:aDecoder)
		cacheDate=aDecoder.decodeObject(forKey: "date") as! Date?
		if let data=aDecoder.decodeObject(forKey: "obj") as? [String]
		{
			for element in data
			{
				if let item=Mapper<T>().map(JSONString: element)
				{
					obj.append(item)
				}
			}
		}
	}
	open class func key(_ params:[String:ApiParam]?)->ApiNetworkRequest
	{
		return ApiNetworkRequest(
			tag: T.tag,
			baseUrl: T.arrayUrl(params),
			params: (params ?? [String:ApiParam]())+T.automaticParams)
	}
	open var obj:[T]=[]
	open var cacheDate:Date?
	open override func encode(with aCoder: NSCoder) {
		cacheDate=timeSource.now()
		aCoder.encode(cacheDate,forKey:"date")
		let jsons:[String]=obj.map { (obj) -> String in
			return Mapper<T>().toJSONString(obj, prettyPrint: false)!
		}
		aCoder.encode(jsons,forKey:"obj")
	}
	init(obj:[T])
	{
		super.init()
		self.obj=obj
	}
}
public protocol APIProtocol
{
	associatedtype MappableType
	associatedtype ApiOutputType
//	func asObservable(_ params:[String:ApiParam]?,progress:APIProgress?)->Observable<MappableType>
}
public protocol CachableAPIProtocol: APIProtocol
{
	associatedtype Cachable : CachableEntity
	func preload(_ params:[String:ApiParam]?,onQueue:OperationQueue)
//	func visitCache(_ params:[String:ApiParam]?,output:PriorityObservable<ApiOutputType>)
	func invalidateCache(_ params:[String:ApiParam]?)
}
public extension CachableAPIProtocol
{
	public func invalidateCache(_ params:[String:ApiParam]?)
	{
		apiCache.invalidate(Cachable.key(params))
	}
}
public protocol CommandAPIProtocol
{
	associatedtype MappableType
	associatedtype ApiOutputType
	associatedtype SubjectType
	func asObservable(_ obj:SubjectType,progress:APIProgress?)->Observable<MappableType>
}
enum CacheAge:String{
	case fresh
	case old
	case expired
}
open class APICommon
{
	public init(){}
	open func preload(_ params:[String:ApiParam]?=nil,onQueue:OperationQueue=APICallsQueue)
	{
		fatalError("must override me!!")
	}
	func checkParams(_ params:[String:ApiParam]?,mandatoryParams:[String])
	{
		if mandatoryParams.isEmpty {return}
		guard let params=params else {fatalError()}
		for p in mandatoryParams
		{
			if params[p] == nil
			{
				fatalError("missing mandatory param \(p)")
			}
		}
	}
	func integrateParams(_ params:inout [String:ApiParam],automaticParams:[String:ApiParam]?)
	{
		guard let automaticParams=automaticParams else {return}
		var newParams=automaticParams
		for (k, v) in params {
			newParams.updateValue(v, forKey: k)
		}
		params=newParams
	}
	var debugLevel:APIDebugLevel=DefaultAPIDebugLevel
	open func setDebugLevel(_ debugLevel:APIDebugLevel)->Self
	{
		self.debugLevel=debugLevel
		return self
	}
	
	fileprivate func _cachedImpl<Cachable,Result>(_ params:[String:ApiParam]?,_:Cachable.Type,_:Result.Type,logTags:[String])->(Cachable.OutputType,CacheAge)? where Cachable:CachableEntity,Result:APISubject
	{
//		dump(params)
		guard let old=apiCache.get(Cachable.key(params)) as? Cachable,
			let date=old.cacheDate
			else {
				log("no \(Cachable.key(params)) in cache",logTags+["api"],debugLevel)
				return nil
		}
		return (old.obj,Result.expiry.age(cachingDate: date))
	}
}
public final class ArrayAPI<Result> : APICommon,CachableAPIProtocol where Result:ObjectWithArrayUrl, Result:APISubject
{
	public override init(){}
	
	public typealias MappableType=Result
	public typealias ApiOutputType=[Result]
	public typealias Cachable=CachableArray<Result>
	
	public override func preload(_ params:[String:ApiParam]?=nil,onQueue:OperationQueue=APICallsQueue)
	{
		log("starting preload task for \(Cachable.key(params))",[Result.tag]+["api"],debugLevel)
		var allParams=params ?? [:]
		integrateParams(&allParams, automaticParams: Result.automaticParams)
		checkParams(allParams, mandatoryParams: Result.mandatoryParams)
		createArrayObservableWithArrayResult(allParams, progress:nil, debugLevel: debugLevel,logTags:[Result.tag])
			.subscribe(onNext: { (array:[Result]) -> Void in
				log("preloaded \(Cachable.key(params))",[Result.tag]+["api"],self.debugLevel)
				let key=Cachable.key(allParams)
				apiCache.set(Cachable(obj:array), forKey: key)
			}).addDisposableTo(globalDisposeBag)
	}
	func visitCache(_ params:[String:ApiParam]?=nil,output:PriorityObservable<[Result]>)->CacheAge?
	{
		var allParams=params ?? [:]
		integrateParams(&allParams, automaticParams: Result.automaticParams)
		checkParams(allParams, mandatoryParams: Result.mandatoryParams)
		if let (cached,age)=_cachedImpl(allParams, Cachable.self, Result.self,logTags:[Result.tag]) {
			log("found \(Cachable.key(params)). It's \(age.rawValue)",[Result.tag,"api"],debugLevel)
			output.onNext(prio:0,value:cached)
			return age
		}
		return nil
	}
	
//	public func asObservable(_ params:[String:ApiParam]?=nil,progress:APIProgress?=nil) -> Observable<Result> {
//		var allParams=params ?? [:]
//		integrateParams(&allParams, automaticParams: Result.automaticParams)
//		checkParams(allParams, mandatoryParams: Result.mandatoryParams)
//		let output=PriorityObservable<Result>()
//		visitCache(allParams,output:output)
//
//		var cacheBuffer=[Result]()
//		let obs:Observable<Result>=createArrayObservableWithItemResult(allParams,progress:progress, debugLevel: debugLevel,logTags:[Result.tag]).shareReplay(API_SHARE_REPLAY_BUFFER).subscribeOn(APIScheduler)
//		obs.subscribe(onNext: { (e:Result) -> Void in
//			cacheBuffer.append(e)
//		}, onError: nil,
//		   onCompleted: { () -> Void in
//			let key=Cachable.key(allParams)
//			apiCache.set(Cachable(obj:cacheBuffer), forKey: key)
//			output.onNext(prio: 1, value: cach)
//		}, onDisposed:nil).addDisposableTo(globalDisposeBag)
//		return obs
//	}
	
	public func asObservableArray(_ params:[String:ApiParam]?=nil,progress:APIProgress?=nil) -> Observable<[Result]> {
		var allParams=params ?? [:]
		integrateParams(&allParams, automaticParams: Result.automaticParams)
		checkParams(allParams, mandatoryParams: Result.mandatoryParams)
		let output=PriorityObservable<[Result]>()
		let cacheAge=visitCache(allParams,output:output)
		if cacheAge != .fresh {
			let obs:Observable<[Result]>=createArrayObservableWithArrayResult(allParams,progress:progress,debugLevel: debugLevel,logTags:[Result.tag]).shareReplay(API_SHARE_REPLAY_BUFFER).subscribeOn(APIScheduler)
			obs.subscribe(onNext: { (array:[Result]) -> Void in
				let key=Cachable.key(allParams)
				apiCache.set(Cachable(obj:array), forKey: key)
				output.onNext(prio: 1, value: array)
			}, onError: nil, onCompleted: nil, onDisposed: nil)
				.addDisposableTo(globalDisposeBag)
		}
		return output.asObservable()
		
	}
	
}

public final class ObjectAPI<Result>: APICommon,CachableAPIProtocol where Result:ObjectWithUrl,Result:APISubject
{
	public override init(){}
	
	public typealias MappableType=Result
	public typealias ApiOutputType=Result
	public typealias Cachable=CachableObject<Result>
	
	public override func preload(_ params:[String:ApiParam]?=nil,onQueue:OperationQueue=APICallsQueue)
	{
		var allParams=params ?? [:]
		integrateParams(&allParams, automaticParams: Result.automaticParams)
		checkParams(allParams, mandatoryParams: Result.mandatoryParams)
		createObjObservable(allParams,progress:nil,debugLevel: debugLevel,logTags:[Result.tag]).subscribe(onNext: {
			(object:Result) -> Void in
			apiCache.set(Cachable(obj:object), forKey: Cachable.key(allParams))
			}).addDisposableTo(globalDisposeBag)
	}
	func visitCache(_ params:[String:ApiParam]?=nil,output:PriorityObservable<Result>)->CacheAge?
	{
		var allParams=params ?? [:]
		integrateParams(&allParams, automaticParams: Result.automaticParams)
		checkParams(allParams, mandatoryParams: Result.mandatoryParams)
		if let (cached,age)=_cachedImpl(allParams, Cachable.self, Result.self,logTags:[Result.tag]) {
			log("found \(Cachable.key(params)). It's \(age.rawValue)",[Result.tag,"api"],debugLevel)
			output.onNext(prio:0,value:cached)
			return age
		}
		return nil
	}
	public func asObservable(_ params:[String:ApiParam]?=nil,progress:APIProgress?=nil) -> Observable<Result> {
		var allParams=params ?? [:]
		integrateParams(&allParams, automaticParams: Result.automaticParams)
		checkParams(allParams, mandatoryParams: Result.mandatoryParams)
		let output=PriorityObservable<Result>()
		visitCache(allParams,output:output)
		
		let obs:Observable<Result>=createObjObservable(allParams,progress:progress, debugLevel: debugLevel,logTags:[Result.tag]).shareReplay(API_SHARE_REPLAY_BUFFER).subscribeOn(APIScheduler)
		obs.subscribe(onNext:{ (e:Result) -> Void in
			let key=Cachable.key(allParams)
			apiCache.set(Cachable(obj:e), forKey: key)
			output.onNext(prio:1,value:e)
		}).addDisposableTo(globalDisposeBag)
		output.currentBest.subscribe(onNext:{print("currentBest:\($0)")})
		return output.asObservable()
	}
}
open class APICallBase
{
	public init?(map:Map) {}
	public init(){}
}
open class APICallBaseObjc:NSObject
{
	public init?(map:Map) {}
	public override init(){}
}
open class APICommandBase: APICallBase
{
	open var success:Bool?
	open var message:String?
	open func mapping(map: Map) {
		success			<- map["success"]
		message			<- map["message"]
	}
	open func isValid()->Bool
	{
		return ok(success) && success!
	}
}
open class APICommandBaseObjc: APICallBaseObjc
{
	open var success:Bool?
	open func mapping(map: Map) {
		success			<- map["success"]
	}
	open func isValid()->Bool
	{
		return ok(success) && success!
	}
}
public protocol APICallWithArrayResult:ObjectWithArrayUrl,APISubject,APIble,WithCachedApi {}

public extension APICallWithArrayResult
{
	typealias APIType=ArrayAPI<Self>
	static func API()->APIType
	{
		return APIType()
	}
	
	static func api(_ progress:ProgressController?=nil,params:[String:Any]?=nil) -> Observable<[Self]> {
 		return API().asObservableArray(progress:progress as? APIProgress)
 	}
 	static func invalidateCache() {
 		API().invalidateCache(nil)
 	}
	static func invalidateCache(_ params:[String:ApiParam]) {
		API().invalidateCache(params)
	}
 }

public protocol APICallWithObjectResult:ObjectWithUrl,APISubject,APIble {}
public extension APICallWithObjectResult
{
	typealias APIType=ObjectAPI<Self>
	static func API()->APIType
	{
		return APIType()
	}
	
}

//public protocol EncryptedAPICallWithObjectResult:ObjectWithUrl,APISubject,APIble {}
//extension EncryptedAPICallWithObjectResult
//{
//	typealias APIType=ObjectEncryptedAPI<Self>
//	static func API()->APIType
//	{
//		return APIType()
//	}
//	
//}

public protocol APICommand:ObjectWithUrl,APIResult,APIble {}
public extension APICommand
{
	typealias APIType=CommandAPI<Self>
	static func API()->APIType
	{
		return APIType()
	}
}

public protocol APICommandWithPreconditions:ObjectWithUrl,APIResult,APIble {
	static func checkPreconditions() throws
}
public extension APICommandWithPreconditions
{
	typealias APIType=CommandAPI<Self>
	static func API() throws ->APIType
	{
		try checkPreconditions()
		return APIType()
	}
}
public protocol AnyString{
	func asString()->String
}
extension String:AnyString {
	public func asString()->String { return self }
}
public extension Dictionary where Key:AnyString {
	public func typeConstrain() -> [String:ApiParam]
	{
		var ret=[String:ApiParam]()
		
		self.nullsRemoved.forEach { (k: AnyString, v: Value) in
			guard let typeSafe=v as? ApiParam else {fatalError()}
			ret[k.asString()]=typeSafe
		}
		return ret
	}
}
extension Dictionary {
	/// An immutable version of update. Returns a new dictionary containing self's values and the key/value passed in.
	func updatedValue(_ value: Value, forKey key: Key) -> Dictionary<Key, Value> {
		var result = self
		result[key] = value
		return result
	}
	
	var nullsRemoved: [Key: Value] {
		let tup = filter { !($0.1 is NSNull) }
		return tup.reduce([Key: Value]()) { $0.0.updatedValue($0.1.value, forKey: $0.1.key) }
	}
}
extension Dictionary where Key:AnyString, Value:ApiParam {
	func typeGeneralize() -> [String:Any]
	{
		var ret=[String:Any]()
		self.forEach { (k:AnyString,v:ApiParam) in
			ret[k.asString()]=v
		}
		return ret
	}
}


extension Map {
	public var typeSafeJSON: [String:ApiParam] {
		return JSON.typeConstrain()
	}
}


public final class CommandAPI<Result>: APICommon,CommandAPIProtocol where Result:APIResult, Result:ObjectWithUrl
	
{
	public override init(){}
	
	public typealias MappableType=Result
	public typealias ApiOutputType=Result
	public typealias SubjectType=Result.SubjectType
	
	func extractJson(_ obj:SubjectType)->[String:ApiParam]
	{
		var mutableObj=obj
		let map = Map(mappingType: .toJSON, JSON: [:])
		Result.mapper(&mutableObj,map)
		logDump(map.currentValue,name:"map.currentValue",["api",Result.tag],.verbose)
		return map.typeSafeJSON
	}

	public func asObservable(_ obj:SubjectType,progress:APIProgress?=nil) -> Observable<Result> {
		if let subj=obj as? APISubject
		{
			subj.invalidateCache()
		}
		
		let obs:Observable<Result>=createObjObservable(extractJson(obj),progress: progress,debugLevel: debugLevel,logTags:[Result.tag])
		return obs
	}
}

public protocol ActivityIndicatable
{
	func activityHandler(style:UIActivityIndicatorViewStyle)->ActivityHandler
	func _showActivity(_ ah:ActivityHandler,style:UIActivityIndicatorViewStyle)
	func _hideActivity()
	
	func __showActivity(style:UIActivityIndicatorViewStyle)
	func __hideActivity()
	func __activityIsShowing()->Bool
	
	// must uniquely identify the object
	func identifier()->Int
}

public extension ActivityIndicatable
{
	func activityHandler(style:UIActivityIndicatorViewStyle)->ActivityHandler
	{
		return ActivityHandler(v:self,style:style)
	}
	func _showActivity(_ ah:ActivityHandler,style:UIActivityIndicatorViewStyle)
	{
		if viewActivityCounters[self.identifier()] == nil
		{
			viewActivityCounters[self.identifier()]=0
		}
		viewActivityCounters[self.identifier()]! += 1
		if viewActivityCounters[self.identifier()] != 1 || __activityIsShowing()
		{
			return
		}
		
		delay(1.0) {
			if let vac=viewActivityCounters[self.identifier()], vac>0 {
				onMain {
					self.__showActivity(style:style)
				}
			}
		}
		
	}
	func _hideActivity()
	{
		if viewActivityCounters[self.identifier()] == nil
		{
			viewActivityCounters[self.identifier()]=0
		}
		viewActivityCounters[self.identifier()]! -= 1
		
		if viewActivityCounters[self.identifier()] != 0 || !__activityIsShowing()
		{
			return
		}
		viewActivityCounters.removeValue(forKey: self.identifier())
		__hideActivity()
	}
}

open class ActivityHandler
{
	let view:ActivityIndicatable
	var alreadyHidden=false
	var showOp:Operation?
	static let ACTIVITY_INDICATOR_TAG=9999
	init(v:ActivityIndicatable,style:UIActivityIndicatorViewStyle)
	{
		view=v
		showOp=BlockOperation {
			self.view._showActivity(self,style:style)
		}
		OperationQueue.main.addOperation(showOp!)
	}
	open func hide()
	{
		alreadyHidden=true
		let hideOp=BlockOperation {
			self.view._hideActivity()
		}
		if let showOp=showOp
		{
			hideOp.addDependency(showOp)
		}
		OperationQueue.main.addOperation(hideOp)
	}
	deinit
	{
		if !alreadyHidden { view._hideActivity() }
	}
}
var viewActivityCounters=[Int:Int]()

extension UIView:ActivityIndicatable
{
	
	public func __showActivity(style:UIActivityIndicatorViewStyle)
	{
		let actInd=UIActivityIndicatorView(activityIndicatorStyle: style)
		actInd.frame=CGRect(x:0,y:0,width:50,height:50)
		actInd.tag=ActivityHandler.ACTIVITY_INDICATOR_TAG
		actInd.backgroundColor=UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.18)
		actInd.layer.cornerRadius=10
		actInd.isHidden=false
		self.addSubview(actInd)
		actInd.center=self.center
		actInd.startAnimating()

	}
	public func __hideActivity()
	{
		if let actInd=self.viewWithTag(ActivityHandler.ACTIVITY_INDICATOR_TAG) as?UIActivityIndicatorView
		{
			actInd.stopAnimating()
			actInd.removeFromSuperview()
		}
	}
	public func __activityIsShowing()->Bool
	{
		return self.viewWithTag(ActivityHandler.ACTIVITY_INDICATOR_TAG) != nil
	}
	public func identifier() -> Int {
		return self.hash
	}
}

extension UIApplication:ActivityIndicatable
{
	public func __showActivity(style: UIActivityIndicatorViewStyle)
	{
		self.isNetworkActivityIndicatorVisible=true
	}
	public func __hideActivity() {
		self.isNetworkActivityIndicatorVisible=false
	}
	public func __activityIsShowing()->Bool
	{
		return self.isNetworkActivityIndicatorVisible
	}
	public func identifier() -> Int {
		return self.hash
	}
	
}




