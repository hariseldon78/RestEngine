//
//  CacheUpdater.swift
//  Municipium
//
//  Created by Roberto Previdi on 11/11/15.
//  Copyright © 2015 Slowmedia. All rights reserved.
//

import Foundation
let _cacheUpdaterInstance=CacheUpdater()
class CacheUpdater
{
	class var instance:CacheUpdater {return _cacheUpdaterInstance}

	let cacheUpdateQueue:OperationQueue={
		let opQ=OperationQueue()
		opQ.qualityOfService=QualityOfService.background
		return opQ
	}()
	func addCacheUpdateOperation(_ key:ApiNetworkRequest,priority:Double,action:@escaping (_ queue:OperationQueue)->Void)
	{
		// TODO: non incodare se c'è già una richiesta con la stessa chiave; mantenere aggiornata questa lista di chiavi
		let operation=Operation()
		operation.completionBlock={
			assertBackground()
			log("#### cache update operation: \(key.tag), priority: \(priority)",["api","cache"],.debug)
			Thread.sleep(forTimeInterval: 1)
			action(self.cacheUpdateQueue)
		}
		// TODO: aggiungere gestione key per non incodare 2 richieste uguali
			switch priority
			{
			case let k where k > 0.75: 	operation.queuePriority = .veryHigh
			case let k where k > 0.3: 	operation.queuePriority = .normal
			default: 					return // non faccio l'aggiornamento, è già stato fatto da poco
		}
		cacheUpdateQueue.addOperation(operation)
	}
}
