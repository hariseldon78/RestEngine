//
//  Validation.swift
//  Municipium
//
//  Created by Roberto Previdi on 22/10/15.
//  Copyright © 2015 Slowmedia. All rights reserved.
//

import Foundation

public func ok(_ obj:String?)->Bool
{
	return obj != nil && obj != ""
}
public func ok<T>(_ obj:T?)->Bool
{
	return obj != nil
}
public func ok(_ obj:String)->Bool
{
	return obj != ""
}
public func ok<T>(_ obj:T)->Bool
{
	return true
}
