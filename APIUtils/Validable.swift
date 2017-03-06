//
//  Validable.swift
//  APIUtils
//
//  Created by Roberto Previdi on 22/09/16.
//  Copyright © 2016 roby. All rights reserved.
//

import Foundation
public protocol ValidityCheckable{
	func isValid()->Bool
}
public protocol Validable:ValidityCheckable{
	var needed:[Validable] {get}
}

extension Validable {
	public var needed:[Validable] {return []}
	public func isValid()->Bool {
		let ret=needed.reduce(true) { (acc, x) in
			if !x.isValid() {
				log("INVALID!!"+String(describing:Self.self),["api"],.error)
			}
			return acc && x.isValid()
		}
		if !ret {
			log("INVALID!",["api"],.error)
		}
		return ret
	}
	public func validate()->Self?
	{
		return isValid() ? self : nil
	}
}

extension Optional:Validable {
	public func isValid() -> Bool {
		switch self {
		case .none:
			log("INVALID!!!"+String(describing:Wrapped.self),["api"],.error)
			return false
		case .some(let wrapped):
			if let validable=wrapped as? Validable {
				return validable.isValid()
			} else {
				return true
			}
		}
	}
}

public struct Valid<T:Validable>
{
	public let wrapped:T
	public init?(_ validable:T) {
		if validable.isValid() {
			wrapped=validable
		} else {
			return nil
		}
	}
	public init?(_ validable:T?) {
		if let validable=validable , validable.isValid() {
			wrapped=validable
		} else {
			return nil
		}
	}
}
