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

public class ProgressHandler {
	class Step:ProgressController {
		let handler:ProgressHandler
		init(handler:ProgressHandler) {
			self.handler=handler
		}
		func start() {
			handler.stepIsStarted()
		}
		func setCompletion(_:CGFloat) {}
		func finish() {
			handler.stepIsDone()
		}
		func cancel() {
			handler.stepIsCanceled()
		}
	}
	let stepLength:CGFloat
	var stepsToFinish=0
	let vc:UIViewController
	var navCon:UINavigationController? {return vc.navigationController}
	public var stepHandlers=[ProgressController]()
	public init(vc:UIViewController,steps:Int)
	{
		self.vc=vc
		stepsToFinish=steps
		stepLength=CGFloat(1.0/CGFloat(steps))
		for _ in 0..<steps {
			stepHandlers.append(Step(handler:self))
		}
	}
	func stepIsStarted() {
		guard let nc=navCon else {return}
		nc.showProgress()
		nc.setIndeterminate(false)
	}
	func stepIsDone() {
		stepsToFinish -= 1
		guard let nc=navCon else {return}
		nc.setProgress(1.0-stepLength*CGFloat(stepsToFinish), animated: true)
		if stepsToFinish==0 {
			nc.finishProgress()
		}
	}
	func stepIsCanceled() {
		stepIsDone()
	}
}

extension ProgressType:ProgressController
{
	
	public func start()
	{
		switch self {
		case .indeterminate(let vc):
			let navCon=vc.navigationController
			navCon?.setIndeterminate(true)
			navCon?.showProgress()
		case .determinate(let step):
			step.start()
		case .none:
			_=0
		}
	}
	public func setCompletion(_:CGFloat)
	{
	}
	public func finish()
	{
		switch self {
		case .indeterminate(let vc):
			let navCon=vc.navigationController
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
			navCon?.finishProgress()
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
