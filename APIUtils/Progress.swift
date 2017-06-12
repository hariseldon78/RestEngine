//
//  APIProgress.swift
//  Municipium
//
//  Created by Roberto Previdi on 14/03/17.
//  Copyright © 2017 municipiumapp. All rights reserved.
//

import Foundation
import DataVisualization
import M13ProgressSuite
import Alamofire

extension M13ProgressView:GenericProgressBar {
	public func setIsIndeterminate(_ indeterminate:Bool) {
		self.indeterminate=indeterminate
	}
	public func show() {
		self.isHidden=false
	}
	public func hide() {
		self.isHidden=true
	}
	public func cancel() {
		setProgress(0, animated: false)
		hide()
	}

}

extension ProgressBarLocation:GenericProgressBar {
	public func setIsIndeterminate(_ indeterminate:Bool) {
		switch self {
		case .inNavBar(let vc):
			vc.navigationController?.setIndeterminate(indeterminate)
		case .inProgressBar(let pb):
			pb.setIsIndeterminate(indeterminate)
		}
	}
	
	public func setProgress(_ progress:CGFloat,animated:Bool) {
		switch self {
		case .inNavBar(let vc):
			vc.navigationController?.setProgress(progress, animated: animated)
		case .inProgressBar(let pb):
			pb.setProgress(progress, animated: animated)
		}
	}
	public func show() {
		switch self {
		case .inNavBar(let vc):
			vc.navigationController?.showProgress()
		case .inProgressBar(let pb):
			pb.show()
		}
	}
	public func hide() {
		switch self {
		case .inNavBar(let vc):
			print(vc.navigationController)
			vc.navigationController?.finishProgress()
		case .inProgressBar(let pb):
			pb.hide()
		}
	}
	public func cancel() {
		switch self {
		case .inNavBar(let vc):
			print(vc.navigationController)
			vc.navigationController?.cancelProgress()
		case .inProgressBar(let pb):
			pb.cancel()
		}
	}
	
}

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
	let pbl:ProgressBarLocation
	let opacity:Bool
	var isStarted=false
	public var stepHandlers=[ProgressController]()
	public init(pbl:ProgressBarLocation,steps:Int,opacity:Bool=false)
	{
		self.pbl=pbl
		self.opacity=opacity
		stepsToFinish=steps
		stepLength=CGFloat(1.0/CGFloat(steps))
		for i in 0..<steps {
			stepHandlers.append(Step(handler:self,id:i))
		}
	}
	func stepIsStarted(_ id:Int) {
		stepCompletions[id]=0
		if isStarted {return}
		switch pbl {
		case .inNavBar(let vc):
			if opacity {
				let opacityView=UIView(frame: vc.view.frame)
				opacityView.backgroundColor=UIColor(white: 0, alpha: 0.5)
				opacityView.tag=9999
				vc.view.addSubview(opacityView)
			}
		default:
			break
		}
		pbl.show()
		pbl.setIsIndeterminate(false)
		isStarted=true
	}
	func stepIsDone(_ id:Int) {
		stepsToFinish -= 1
		if stepsToFinish==0 {
			switch pbl {
			case .inNavBar(let vc):
				if let opacityView=vc.view.viewWithTag(9999) {
					opacityView.removeFromSuperview()
				}
			default:
				break
			}
			pbl.hide()
		} else {
			stepCompletions[id]=stepLength
			updateProgress()
		}
	}
	func updateProgress() {
		let totalCompletion=stepCompletions
			.map { (_, value) in return value }
			.reduce(CGFloat(0), +)
		log("total progress:\(totalCompletion)", tags: ["progress"], level: .verbose)
		
		pbl.setProgress(totalCompletion, animated: true)
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
public class APIProgress:ProgressController{
	var type:ProgressType
	public init(type:ProgressType){
		self.type=type
	}
	var startTime:Date?
	var pbl:ProgressBarLocation? {
		switch type {
		case .indeterminate(let pbl):
			return pbl
		case .determinate(let step):
			return (step as! ProgressHandler.Step).handler.pbl
		default:
			return nil
		}
	}
	public func start()
	{
		startTime=Date()
		DispatchQueue.main.async {
			switch self.type {
			case .indeterminate(let pbl):
				switch pbl {
				case .inNavBar(let vc):
					let navCon=vc.navigationController
					navCon?.showProgress()
					navCon?.setIndeterminate(true)
				case .inProgressBar(let pb):
					pb.show()
					pb.setIsIndeterminate(true)
				}
			case .determinate(let step):
				step.start()
			case .none:
				_=0
			}
		}
	}
	public func setIndeterminate() {
		if let pbl=pbl{
			pbl.setIsIndeterminate(true)
			type = .indeterminate(pbl:pbl)
		}
		start()
	}
	
	public func setCompletion(_ fraction:CGFloat,eta:TimeInterval)
	{
		log("prog: \(fraction); eta: \(eta)", tags: ["progress"], level: .verbose)
		switch type {
		case .indeterminate(let pbl):
			if fraction>0.0 && eta>0.5 {
				log("APIProgress will become determinate", tags: ["progress"], level: .verbose)
				let ph=ProgressHandler(pbl:pbl, steps: 1)
				let step=ph.stepHandlers[0]
				type = .determinate(step:step)
				step.start()
				step.setCompletion(fraction,eta:eta)
			}
		case .determinate(let step):
			log("set determinate progress:\(fraction)", tags: ["progress"], level: .verbose)
			step.setCompletion(fraction,eta:eta)
		case .none:
			_=0
		}
	}
	public func setCompletion(progress:Alamofire.Progress,start:Date) {
		let fraction=progress.fractionCompleted
		let elapsedTime=Date().timeIntervalSince(startTime ?? start)
		let eta=elapsedTime*(1.0-fraction)/fraction
		setCompletion(CGFloat(fraction),eta:eta)
		
	}
	public func finish()
	{
		switch type {
		case .indeterminate(let pbl):
			pbl.hide()
		case .determinate(let step):
			step.setCompletion(1.0, eta: 0)
			delay(0.2) {
				step.finish()
			}
		case .none:
			_=0
		}
		
	}
	public func cancel()
	{
		switch type {
		case .indeterminate(let pbl):
			pbl.cancel()
		case .determinate(let step):
			step.cancel()
		case .none:
			_=0
		}
	}
	
}

public extension UIViewController {
	public var progress:APIProgress {
		//		let ph=ProgressHandler(vc: self, steps: 2)
		//		return .determinate(step:ph.stepHandlers[0])
		return APIProgress(type: .indeterminate(pbl: .inNavBar(vc: self)))
	}
	
}
