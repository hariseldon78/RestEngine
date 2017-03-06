//
//  Cache.swift
//  Municipium
//
//  Created by Roberto Previdi on 12/09/16.
//  Copyright © 2016 municipiumapp. All rights reserved.
//
import PINCache
import ObjectMapper
import Foundation

extension Sequence where Iterator.Element: Equatable {
	var uniqueElements: [Iterator.Element] {
		return self.reduce([]){uniqueElements, element in
			uniqueElements.contains(element)
				? uniqueElements
				: uniqueElements + [element]
		}
	}
}

open class Cache<Key:Mappable,Value:NSCoding> {
	let name:String
	let cache:PINCache
	public init(name:String) {
		self.name=name
		cache=PINCache(name:name)
	}
	open func set(_ value:Value, forKey key:Key){
		let keyS=Cache.toString(key)
		assert(!keyS.isEmpty)
		cache.setObject(value,forKey:keyS)
	}
	open func get(_ key:Key)->Value? {
		return cache.object(forKey: Cache.toString(key)) as? Value
	}
	open func invalidate(_ key:Key) {
		cache.removeObject(forKey: Cache.toString(key))
	}
	open func invalidate(_ predicate:@escaping (Key)->Bool)->Int {
		var keysToRemove=[String]()
		cache.memoryCache.enumerateObjects(block: { (_,keyString,_) in
			if let key=Cache.fromString(keyString) , predicate(key) {
				keysToRemove.append(keyString)
			}
		})
		
		cache.diskCache.enumerateObjects(block: { (_,keyString,_,_) in
			if let key=Cache.fromString(keyString) , predicate(key) {
				keysToRemove.append(keyString)
			}
		})
		
		let keys=keysToRemove.uniqueElements
		keys.forEach{ key in
			cache.removeObject(forKey: key)
		}
		
		return keys.count
		
	}
	
	open func clear() {
		cache.removeAllObjects()
	}
	
	static func toString(_ key:Key)->String {
		return key.toJSONString() ?? ""
	}
	
	static func fromString(_ s:String)->Key? {
		if Mapper<Key>.parseJSONString(JSONString: s) != nil {
			return Key(JSONString:s)
		} else {
			return nil
		}
	}
}
