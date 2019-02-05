//
//  InterfaceController.swift
//  metric-stack WatchKit Extension
//
//  Created by Jason DuPertuis on 1/19/19.
//  Copyright © 2019 jdp. All rights reserved.
//

import WatchKit
import Foundation
import HealthKit

class InterfaceController: WKInterfaceController {

    @IBOutlet weak var heartRateLabel: WKInterfaceLabel!
    @IBOutlet weak var stepsLabel: WKInterfaceLabel!
    @IBOutlet weak var caloriesLabel: WKInterfaceLabel!
    
    let healthKitInterface = HealthKitInterface()
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
        
        healthKitInterface.observerHeartRateSamples() {
            (heartRate) in self.heartRateLabel.setText("\(Int(heartRate))")
        }
        
        healthKitInterface.observeStepSamples() {
            (steps) in
            var display = "--"
            
            if steps != nil {
                display = "\(Int(steps ?? 0.0))"
            }
            
            self.stepsLabel.setText(display)
        }
        
        healthKitInterface.observeCalorieSamples() {
            calories in
            var display = "--"
            
            if calories != nil {
                display = "\(Int(calories ?? 0.0))"
            }
            
            self.caloriesLabel.setText(display)
        }
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
}
