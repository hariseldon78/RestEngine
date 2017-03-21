//
//  Progress.swift
//  Municipium
//
//  Created by Roberto Previdi on 14/03/17.
//  Copyright © 2017 municipiumapp. All rights reserved.
//

import Foundation
import M13ProgressSuite
import DataVisualization
import Alamofire

public class ProgressHandler {
	class Step:ProgressController {
		let handler:ProgressHandler
		let id:Int
		init(handler:ProgressHandler,id:Int) {
			self.handler=handler
			self.id=id
		}
		func start() {
			handler.stepIsStarted(id)
		}
		func setCompletion(_ v:CGFloat,eta:TimeInterval) {
			handler.setStepCompletion(id,v)
		}
		func finish() {
			handler.stepIsDone(id)
		}
		func cancel() {
			handler.stepIsCanceled(id)
		}
	}
	let stepLength:CGFloat
	var stepsToFinish=0
	var stepCompletions=[Int:CGFloat]()
	let vc:UIViewController
	let opacity:Bool
	var isStarted=false
	var navCon:UINavigationController? {return vc.navigationController}
	public var stepHandlers=[ProgressController]()
	public init(vc:UIViewController,steps:Int,opacity:Bool=false)
	{
		self.vc=vc
		self.opacity=opacity
		stepsToFinish=steps
		stepLength=CGFloat(1.0/CGFloat(steps))
		for i in 0..<steps {
			stepHandlers.append(Step(handler:self,id:i))
		}
	}
	func stepIsStarted(_ id:Int) {
		guard let nc=navCon else {return}
		stepCompletions[id]=0
		if isStarted {return}
		let opacityView=UIView(frame: vc.view.frame)
		opacityView.backgroundColor=UIColor(white: 0, alpha: 0.5)
		opacityView.tag=9999
		vc.view.addSubview(opacityView)
		nc.showProgress()
		nc.setIndeterminate(false)
	}
	func stepIsDone(_ id:Int) {
		stepsToFinish -= 1
		if stepsToFinish==0 {
			guard let nc=navCon else {return}
			nc.finishProgress()
			if let opacityView=vc.view.viewWithTag(9999) {
				opacityView.removeFromSuperview()
			}
		} else {
			stepCompletions[id]=stepLength
			updateProgress()
		}
	}
	func updateProgress() {
		guard let nc=navCon else {return}
		let totalCompletion=stepCompletions
			.map { (_, value) in return value }
			.reduce(CGFloat(0), +)
		nc.setProgress(totalCompletion, animated: true)
	}
	func setStepCompletion(_ id:Int,_ v:CGFloat) {
		stepCompletions[id]=v/CGFloat(stepHandlers.count)
		updateProgress()
	}
	func stepIsCanceled(_ id:Int) {
		stepCompletions[id]=0
		updateProgress()
	}
}

extension ProgressType:ProgressController
{
	
	public func start()
	{
		switch self {
		case .indeterminate(let vc):
			let navCon=vc.navigationController
			navCon?.showProgress()
			navCon?.setIndeterminate(true)
		case .determinate(let step):
			step.start()
		case .none:
			_=0
		}
	}
	public func setCompletion(_ fraction:CGFloat,eta:TimeInterval)
	{
		print("prog: \(fraction); eta: \(eta)")
		switch self {
		case .indeterminate(let vc):
			print("@@@@@@@@@@@@@@@@@@@@ progress indeterminate:\(fraction)")
			_=0
		case .determinate(let step):
			step.setCompletion(fraction,eta:eta)
		case .none:
			_=0
		}
	}
	public func setCompletion(progress:Alamofire.Progress,start:Date) {
		let fraction=progress.fractionCompleted
		let elapsedTime=Date().timeIntervalSince(start)
		let eta=elapsedTime*(1.0-fraction)/fraction
		setCompletion(CGFloat(fraction),eta:eta)

	}
	public func finish()
	{
		switch self {
		case .indeterminate(let vc):
			let navCon=vc.navigationController
			log("isShowingProgressBar():\(navCon?.isShowingProgressBar())", tags: ["progress"], level: .verbose)
			navCon?.finishProgress()
		case .determinate(let step):
			step.finish()
		case .none:
			_=0
		}

	}
	public func cancel()
	{
		switch self {
		case .indeterminate(let vc):
			let navCon=vc.navigationController
			navCon?.cancelProgress()
		case .determinate(let step):
			step.cancel()
		case .none:
			_=0
		}
	}

}

public extension UIViewController {
	public var progressType:ProgressType {
//		let ph=ProgressHandler(vc: self, steps: 2)
//		return .determinate(step:ph.stepHandlers[0])
		return .indeterminate(viewController:self)
	}
	
}
