//
//  Utils.swift
//  APIUtils
//
//  Created by Roberto Previdi on 28/02/17.
//  Copyright © 2017 roby. All rights reserved.
//

import Foundation

public func delay(_ delay:Double, closure:@escaping ()->()) {
	DispatchQueue.main.asyncAfter(
		deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
}

public func onMain(_ f:@escaping ()->Void) {
	OperationQueue.main.addOperation{
		f()
	}
}
