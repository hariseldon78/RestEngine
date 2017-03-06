////
////  APIUtilsTests.swift
////  APIUtilsTests
////
////  Created by Roberto Previdi on 11/11/15.
////  Copyright © 2015 roby. All rights reserved.
////
//
//import XCTest
//@testable import APIUtils
//import ObjectMapper
//import Alamofire
//import RxSwift
//
//protocol UrlProvider{
//	static var url:String {get}
//}
//
//
//class GoodUrl:UrlProvider{
//	static let url="http://localhost:7080/hello/world"
//}
//
//class NotExistsUrl:UrlProvider{
//	static let url="http://localhost:7080/not/exists"
//}
//
//class NeverReturnUrl:UrlProvider{
//	static let url="http://localhost:7080/never/returns"
//}
//
//class SometimeReturnUrl:UrlProvider{
//	static let url="http://localhost:7080/sometimes/returns"
//}
//
////class SlowUrl:UrlProvider{
////	static let url="http://localhost:7080/slow"
////}
//
//class MicroServerTest<UrlClass:UrlProvider>:APICallWithObjectResult
//{
//	var text:String?
//	var number:Int?
//	required init() {}
//	required init?(map: Map) {}
//	func mapping(map: Map) {
//		text	<- map["text"]
//		number	<- map["number"]
//	}
//	
//	class func url(params: [String : AnyObject]?) -> String {
//		//TESTARE DA SIMULATORE, O CAMBIARE LA URL
//		return UrlClass.url
//	}
//	
//	typealias API=ObjectAPI<MicroServerTest>
//	static var expiryHours:UInt {return 0}
//	static var method:Alamofire.HTTPMethod {return Alamofire.HTTPMethod.get}
//}
//
//class APIUtilsTests: XCTestCase {
//	
//	func testGood() {
//		let disposeBag=DisposeBag()
//		let exp=expectationWithDescription("")
//		MicroServerTest<GoodUrl>.API().asObservable(view: nil).subscribe(
//			onNext: {
//				(mst) -> Void in
//				XCTAssertEqual(mst.text, "Hello world")
//				XCTAssertEqual(mst.number, 5)
//				exp.fulfill()
//			},
//			onError: { (error) -> Void in
//				XCTFail()
//			}, onCompleted: nil, onDisposed: nil)
//			.addDisposableTo(disposeBag)
//		waitForExpectationsWithTimeout(10, handler: nil)
//	}
//	
//	func testNotExistsUrl() {
//		let disposeBag=DisposeBag()
//		let exp=expectationWithDescription("")
//		MicroServerTest<NotExistsUrl>.API().asObservable(view: nil).subscribe(
//			onNext: {
//				(mst) -> Void in
//				XCTFail()
//			},
//			onError: { (error) -> Void in
//				dump(error)
//				exp.fulfill()
//			}, onCompleted: nil, onDisposed: nil)
//			.addDisposableTo(disposeBag)
//		waitForExpectationsWithTimeout(10, handler: nil)
//	}
//	
//	func testNeverReturnUrl() {
//		let disposeBag=DisposeBag()
//		let exp=expectationWithDescription("")
//		MicroServerTest<NeverReturnUrl>.API().asObservable(view: nil).subscribe(
//			onNext: {
//				(mst) -> Void in
//				XCTFail()
//			},
//			onError: { (error) -> Void in
//				dump(error)
//				exp.fulfill()
//			}, onCompleted: nil, onDisposed: nil)
//			.addDisposableTo(disposeBag)
//		waitForExpectationsWithTimeout(60, handler: nil)
//	}
//	
//	
//	func testSometimeReturnUrl() {
//		let disposeBag=DisposeBag()
//		let exp=expectationWithDescription("")
//		MicroServerTest<SometimeReturnUrl>.API().asObservable(view: nil)
//			.subscribe(
//			onNext: {
//				(mst) -> Void in
//				XCTAssertEqual(mst.text, "Hello world")
//				XCTAssertEqual(mst.number, 5)
//				exp.fulfill()
//			},
//			onError: { (error) -> Void in
//				dump(error)
//				XCTFail()
//			}, onCompleted: nil, onDisposed: nil)
//			.addDisposableTo(disposeBag)
//		waitForExpectationsWithTimeout(10, handler: nil)
//	}
//	
//	func testRxReplayShareReplay() {
//		let disposeBag=DisposeBag()
//		let obs=create { (observer:AnyObserver<Int>) -> Disposable in
//			observer.onError(NSError(domain: "big problem", code: -1, userInfo: nil))
//			return AnonymousDisposable{}
//		}
//		
//		let exp1=expectationWithDescription("")
//		let exp2=expectationWithDescription("")
//		
//		let shared=obs.retry(3).shareReplay(10)
//		shared.subscribe(
//			onNext: { (_) -> Void in
//				XCTFail()
//			},
//			onError: { (e) -> Void in
//				let e=e as NSError
//				XCTAssertEqual(e.domain, "big problem")
//				exp1.fulfill()
//			}, onCompleted: nil, onDisposed: nil)
//			.addDisposableTo(disposeBag)
//		
//		shared.subscribe(
//			onNext: { (_) -> Void in
//			XCTFail()
//			},
//			onError: { (e) -> Void in
//				let e=e as NSError
//				XCTAssertEqual(e.domain, "big problem")
//				exp2.fulfill()
//			}, onCompleted: nil, onDisposed: nil)
//		.addDisposableTo(disposeBag)
//		
//		waitForExpectationsWithTimeout(10, handler: nil)
//		
//		
//	}
//	
//}
