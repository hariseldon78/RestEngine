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
	public init(showConnectionToast: ((ConnectionStatus)->(Bool))?=nil)
	{
		self.showConnectionToast=showConnectionToast
		reachability.reachableOnWWAN=true
		NotificationCenter.default.rx.notification(ReachabilityChangedNotification)
			.subscribe(onNext:{notif in
				guard let reachability=notif.object as? Reachability else {return}
				let status=reachability.currentReachabilityStatus
				print("status:\(status)")
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
			Observable<Int>.interval(5, scheduler: MainScheduler.instance)
				.filter{_ in self.rxOnline.value == .offline}
				.map{_ in return()}
			])
			// verifico la connessione con un ping a google
			.map{ _ in
				return self.httping(url: URL(string: "http://google.com")!)
			}
			.switchLatest()
			.distinctUntilChanged()
			// e trasporto il risultato in rxOnline
			.subscribe(onNext: { (online) in
				self.rxOnline.value=online
			}).addDisposableTo(🗑)
		
		rxOnline.asObservable()
			.do(onNext:{print("=============ONLINE:\($0.rawValue)")})
			.subscribe(onNext: showStatus)
			.addDisposableTo(🗑)
	}
	var lastStatusShown:ConnectionStatus?
	func showStatus(status:ConnectionStatus) {
		print("++++++++++++++++++ONLINE:\(status.rawValue) _showConnectionToast:\(self.showConnectionToast != nil)")
		if lastStatusShown != status && showConnectionToast?(status) ?? false {
			lastStatusShown=status
		}
	}
	
	func httping(url:URL)->Observable<ConnectionStatus>
	{
		return Observable.create({ (observer) -> Disposable in
			let config=URLSessionConfiguration.default
			config.timeoutIntervalForRequest=0.5
			config.timeoutIntervalForResource=0.5
			config.requestCachePolicy = .reloadIgnoringCacheData
			print("trying to contact google")
			URLSession(configuration:config).dataTask(with:url,completionHandler:{(data,response,error) in
				print("done: \(String(describing: response)), \(String(describing: error))")
				observer.onNext(error==nil ? .online : .offline)
			}).resume()
			return Disposables.create()
		})
	}
}
