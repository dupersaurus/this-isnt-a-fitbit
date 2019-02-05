//
//  ViewController.swift
//  metric-stack
//
//  Created by Jason DuPertuis on 1/19/19.
//  Copyright © 2019 jdp. All rights reserved.
//

import UIKit



class ViewController: UIViewController {

    let healthKitInterface = HealthKitInterface()
    
    @IBOutlet weak var hrDisplay: UILabel!
    @IBOutlet weak var stepsDisplay: UILabel!
    @IBOutlet weak var caloriesDisplay: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        healthKitInterface.observerHeartRateSamples() {
            (heartRate) in
            var display = "--"
            
            if heartRate != nil {
                display = "\(Int(heartRate ?? 0.0))"
            }
            
            self.hrDisplay.text = display
        }
        
        healthKitInterface.observeStepSamples() {
            (steps) in
            var display = "--"
            
            if steps != nil {
                display = "\(Int(steps ?? 0.0))"
            }
            
            self.stepsDisplay.text = display
        }
        
        healthKitInterface.observeCalorieSamples() {
            calories in
            var display = "--"
            
            if calories != nil {
                display = "\(Int(calories ?? 0.0))"
            }
            
            self.caloriesDisplay.text = display
        }
    }


    @IBAction func onOpenWatchApp(_ sender: Any) {
        healthKitInterface.startWatchApp()
    }
    
    @IBAction func simulateHR(_ sender: Any) {
        healthKitInterface.writeDebugData()
    }
}

