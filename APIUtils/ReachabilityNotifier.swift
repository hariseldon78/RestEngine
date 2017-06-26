//
//  ReachabilityNotifier.swift
//  APIUtils
//
//  Created by Roberto Previdi on 14/06/17.
//  Copyright © 2017 roby. All rights reserved.
//

import Foundation
import RxSwift
import Reachability

public enum ConnectionStatus:String{
	case online
	case offline
	
	var isOnline:Bool {return self == .online}
}

public class ReachabilityNotifier {
	//#if arch(i386) || arch(x86_64)
	public let rxReachability=Variable<Reachability.NetworkStatus>(.reachableViaWiFi)
	public let rxOnline=Variable<ConnectionStatus>(.online)
	//#else
	//public let rxReachability=Variable<Reachability.NetworkStatus>(.notReachable)
	//#endif
	public let reachability:Reachability=Reachability(hostname:"http://google.com")!
	public var showConnectionToast:((ConnectionStatus)->(Bool))?
	let 🗑=DisposeBag()
	var	networkActivityLock=NSRecursiveLock()
	var networkActivityCounter=0
	public init(showConnectionToast: ((ConnectionStatus)->(Bool))?=nil)
	{
		self.showConnectionToast=showConnectionToast
		reachability.reachableOnWWAN=true
		NotificationCenter.default.rx.notification(ReachabilityChangedNotification)
			.subscribe(onNext:{notif in
				// non sempre triggera quando si va offline
				log("reachability changed notification",["online"])
				guard let reachability=notif.object as? Reachability else {return}
				let status=reachability.currentReachabilityStatus
				log("reachability status:\(status)",["online"])
				#if !arch(i386) && !arch(x86_64) // non simulatore
					self.rxReachability.value=reachability.currentReachabilityStatus
				#endif
			}).addDisposableTo(🗑)
		try! reachability.startNotifier()
		
		Observable<Void>.merge([
			// ad ogni cambio di reachability, con una latenza di un secondo, e collassando i bursts di riconnessione
			
			rxReachability
				.asObservable()
				.delay(1, scheduler: MainScheduler.instance)
				//				.debounce(0.2, scheduler: MainScheduler.instance)
				.map{_ in return ()}
			,
			
			// oppure ogni 5 secondi, se siamo offline
			// anche se siamo online, ho visto che la notifica non arriva sempre quando si va offline
			
			Observable<Int>.interval(5, scheduler: MainScheduler.instance)
				.filter{_ in self.rxOnline.value == .offline}
				.map{_ in return()},
			Observable<Int>.interval(15, scheduler: MainScheduler.instance)
				.filter{_ in self.rxOnline.value == .online}
				.map{_ in return()}])
			
			// verifico la connessione con un ping a google
			.map{ _ in
				return self.httping(url: URL(string: "http://google.com")!)
			}
			.do{ v in
				log("httping executed: \(v)",["online"])
			}
			.switchLatest()
			.debug("rxOnline pre distinct", trimOutput: false)
			.distinctUntilChanged()
			.debug("rxOnline post distinct", trimOutput: false)
			// e trasporto il risultato in rxOnline
			.subscribe(onNext: { (online) in
				self.rxOnline.value=online
			}).addDisposableTo(🗑)
		
		rxOnline.asObservable()
			.do(onNext:{
				log("=============ONLINE:\($0.rawValue)",["online"])
			})
			.subscribe(onNext: showStatus)
			.addDisposableTo(🗑)
		
		/*
notificationCenter.addObserver(
self,
selector: #selector(NetworkActivityIndicatorManager.networkRequestDidStart),
name: Notification.Name.Task.DidResume,
object: nil
)*/
		NotificationCenter.default.rx.notification(Notification.Name.Task.DidResume).subscribe(onNext:{_ in
			print("==================== NETWORK ACTIVITY DETECTED =========================")
			self.networkActivityLock.lock()
			defer {self.networkActivityLock.unlock()}
			self.networkActivityCounter+=1
		}).addDisposableTo(🗑)
		NotificationCenter.default.rx.notification(Notification.Name.Task.DidComplete).subscribe(onNext:{_ in
			print("==================== NETWORK ACTIVITY COMPLETED ########################")
			self.networkActivityLock.lock()
			defer {self.networkActivityLock.unlock()}
			self.networkActivityCounter-=1
		}).addDisposableTo(🗑)
	}
	// impedisco che mostri il toast all'inizio
	var lastStatusShown:ConnectionStatus = .online
	func showStatus(status:ConnectionStatus) {
		log("++++++++++++++++++ONLINE:\(status.rawValue) _showConnectionToast:\(self.showConnectionToast != nil)",["online"])
		if lastStatusShown != status && showConnectionToast?(status) ?? false {
			log("*******************ONLINE:\(status.rawValue) _showConnectionToast:\(self.showConnectionToast != nil)",["online"])
			lastStatusShown=status
		}
	}
	
	func httping(url:URL)->Observable<ConnectionStatus>
	{
		return Observable.create({ (observer) -> Disposable in
			self.networkActivityLock.lock()
			guard self.networkActivityCounter==0 else  {
				observer.onNext(.online)
				observer.onCompleted()
				self.networkActivityLock.unlock()
				return Disposables.create()
			}
			self.networkActivityLock.unlock()
			let config=URLSessionConfiguration.default
			config.timeoutIntervalForRequest=3
			config.timeoutIntervalForResource=3
			config.requestCachePolicy = .reloadIgnoringCacheData
			log("trying to contact google",["online"])
			URLSession(configuration:config).dataTask(with:url,completionHandler:{(data,response,error) in
				log("done: \(String(describing: response)), \(String(describing: error))",["online"])
				observer.onNext(error==nil ? .online : .offline)
				observer.onCompleted()
			}).resume()
			return Disposables.create()
		})
	}
}

//extension Notification.Name {
//	/// Used as a namespace for all `URLSessionTask` related notifications.
//	public struct Task {
//		/// Posted when a `URLSessionTask` is resumed. The notification `object` contains the resumed `URLSessionTask`.
//		public static let DidResume = Notification.Name(rawValue: "org.alamofire.notification.name.task.didResume")
//		
//		/// Posted when a `URLSessionTask` is suspended. The notification `object` contains the suspended `URLSessionTask`.
//		public static let DidSuspend = Notification.Name(rawValue: "org.alamofire.notification.name.task.didSuspend")
//		
//		/// Posted when a `URLSessionTask` is cancelled. The notification `object` contains the cancelled `URLSessionTask`.
//		public static let DidCancel = Notification.Name(rawValue: "org.alamofire.notification.name.task.didCancel")
//		
//		/// Posted when a `URLSessionTask` is completed. The notification `object` contains the completed `URLSessionTask`.
//		public static let DidComplete = Notification.Name(rawValue: "org.alamofire.notification.name.task.didComplete")
//	}
//}
