//
//  Utils.swift
//  APIUtils
//
//  Created by Roberto Previdi on 28/02/17.
//  Copyright © 2017 roby. All rights reserved.
//

import UIKit
import Alamofire
import RxSwift
import AlamofireImage

public func delay(_ delay:Double, closure:@escaping ()->()) {
	DispatchQueue.main.asyncAfter(
		deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
}

public func onMain(_ f:@escaping ()->Void) {
//	OperationQueue.main.addOperation
	DispatchQueue.main.async(execute:f)
}


extension UIImage {
	public static func download(from url:String,viewForActivityIndicator view:UIView?)->Observable<UIImage> {
		return Observable.create({ (observer) -> Disposable in
			var actInd:ActivityHandler?
			if let view=view {
				actInd=ActivityHandler(v:view,style:.whiteLarge)
			}
			Alamofire.request(url).responseImage{ response in
				switch response.result{
				case .success(let image):
					observer.onNext(image)
					observer.onCompleted()
				case .failure(let error):
					observer.onError(error)
				}
				actInd?.hide()
			}
			return Disposables.create()
		})
	}
}

public final class PriorityObservable<Element>: Cancelable {
	let source = PublishSubject<(prio:Int,value:Element)>()
	let currentBest = BehaviorSubject<(Int,Element?)>(value: (-1,nil))
	public var isDisposed: Bool { return source.isDisposed || currentBest.isDisposed }
	public func dispose() {
		source.dispose()
		currentBest.dispose()
		sourceSubscription?.dispose()
	}
	func onNext(prio:UInt,value:Element) {
		source.onNext((prio:Int(prio),value:value))
	}
	func onCompleted() {
		currentBest.onCompleted()
	}
	func onError(error: Error) {
		currentBest.onError(error)
	}
	func asObservable() -> Observable<Element> {
		return currentBest.filter{$0.0 > -1}.map{$0.1!}
	}
	func subscribe<O>(_ observer: O) -> Disposable where O : ObserverType, O.E == Element {
		return asObservable().subscribe(observer)
	}
	var sourceSubscription:Disposable?=nil
	init() {
		sourceSubscription=source.filter({ (prio,_) -> Bool in
			guard let current=try? self.currentBest.value() else {return false}
			let isHigherPriority = prio > -1 && prio>=current.0
			return isHigherPriority
		}).subscribe(onNext:{ (prio,v) in
			self.currentBest.onNext((prio, v))
		})
	}
}

