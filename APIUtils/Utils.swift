//
//  Utils.swift
//  APIUtils
//
//  Created by Roberto Previdi on 28/02/17.
//  Copyright © 2017 roby. All rights reserved.
//

import Foundation
import Alamofire
import RxSwift
import AlamofireImage


public func delay(_ delay:Double, closure:@escaping ()->()) {
	DispatchQueue.main.asyncAfter(
		deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
}

public func onMain(_ f:@escaping ()->Void) {
	OperationQueue.main.addOperation{
		f()
	}
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
