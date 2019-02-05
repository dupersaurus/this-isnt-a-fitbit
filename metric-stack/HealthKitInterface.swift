//
//  HealthKitInterface.swift
//  metric-stack
//
//  Created by Jason DuPertuis on 1/20/19.
//  Copyright © 2019 jdp. All rights reserved.
//

import Foundation
import HealthKit
import WatchConnectivity

class HealthKitInterface {
    
    private let healthStore: HKHealthStore?
    private let readableTypes: Set<HKQuantityType>?
    private let writeableTypes: Set<HKQuantityType>?
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil;
    var validSession: WCSession? {
        #if os(iOS)
        if let session = session, session.isPaired && session.isWatchAppInstalled {
            return session
        }
        #elseif os(watchOS)
        return session
        #endif
        return nil
    }
    
    private var heartRateObserverQuery: HKObserverQuery?
    private var stepObserverQuery: HKObserverQuery?
    
    init() {
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
            self.readableTypes = Set([HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
                                HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
                                HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
                                HKObjectType.quantityType(forIdentifier: .heartRate)!,
                                HKObjectType.quantityType(forIdentifier: .stepCount)!,
                                HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!])
            self.writeableTypes = Set([
                HKObjectType.quantityType(forIdentifier: .heartRate)!,
                HKObjectType.quantityType(forIdentifier: .stepCount)!,
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
                HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
            ])
            
            self.healthStore?.requestAuthorization(toShare: self.writeableTypes, read: self.readableTypes) { (success, error) in
                if success {
                    print("HealthStore set up")
                } else {
                    print(error.debugDescription)
                }
            }
        } else {
            self.healthStore = nil
            self.readableTypes = nil
            self.writeableTypes = nil
        }
    }
    
    // ****** Observe Heart Rate
    func observerHeartRateSamples(listener: @escaping (Double?) -> Void) {
        let heartRateSampleType = HKObjectType.quantityType(forIdentifier: .heartRate)
        
        if let observerQuery = heartRateObserverQuery {
            healthStore?.stop(observerQuery)
        }
        
        heartRateObserverQuery = HKObserverQuery(sampleType: heartRateSampleType!, predicate: nil) { (_, _, error) in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }
            
            self.fetchLatestHeartRateSample { (sample) in
                guard let sample = sample else {
                    print("No HR sample")
                    listener(nil)
                    return
                }
                
                DispatchQueue.main.async {
                    let heartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                    print("Heart Rate Sample: \(heartRate)")
                    listener(heartRate)
                }
            }
        }
        
        healthStore?.execute(heartRateObserverQuery!)
    }
    
    func fetchLatestHeartRateSample(completionHandler: @escaping (_ sample: HKQuantitySample?) -> Void) {
        guard let sampleType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else {
            completionHandler(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: sampleType,
                                  predicate: predicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor]) { (_, results, error) in
                                    if let error = error {
                                        print("Error: \(error.localizedDescription)")
                                        return
                                    }
                                    
                                    if (results?.count == 0) {
                                        completionHandler(nil);
                                    } else {
                                        completionHandler(results?[0] as? HKQuantitySample)
                                    }
        }
        
        healthStore?.execute(query)
    }
    
    // ****** Observe Steps
    func observeStepSamples(listener: @escaping (Double?) -> Void) {
        let calendar = NSCalendar.current
        let interval = NSDateComponents()
        interval.day = 1
        
        var anchorComponents = calendar.dateComponents([Calendar.Component.day, Calendar.Component.month, Calendar.Component.year], from: NSDate() as Date)
        anchorComponents.hour = 0;
        anchorComponents.minute = 0;
        
        guard let anchorDate = calendar.date(from: anchorComponents) else {
            fatalError("*** unable to create a valid date from the given components ***")
        }
        
        guard let quantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount) else {
            fatalError("*** Unable to create a step count type ***")
        }
        
        // Create the query
        let query = HKStatisticsCollectionQuery(quantityType: quantityType,
                                                quantitySamplePredicate: nil,
                                                options: .cumulativeSum,
                                                anchorDate: anchorDate,
                                                intervalComponents: interval as DateComponents)
        
        query.initialResultsHandler = {
            query, results, error in
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
                fatalError("*** Unable to get step statistics for day ***")
            }
            
            DispatchQueue.main.async {
                let count = dayStats.sumQuantity()?.doubleValue(for: HKUnit.count())
                print("Step Sample: \(String(describing: count))")
                listener(count)
            }
        }
        
        query.statisticsUpdateHandler = {
            query, results, collection, error in
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            /*guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
                fatalError("*** Unable to get step statistics for day ***")
            }*/
            
            DispatchQueue.main.async {
                let count = statsCollection.sumQuantity()?.doubleValue(for: HKUnit.count())
                print("Step Sample: \(count)")
                listener(count)
            }
        }
        
        healthStore?.execute(query)
    }
    
    // ****** Observe calories
    func observeCalorieSamples(listener: @escaping (Double?) -> Void) {
        let calendar = NSCalendar.current
        let interval = NSDateComponents()
        interval.day = 1
        
        var anchorComponents = calendar.dateComponents([Calendar.Component.day, Calendar.Component.month, Calendar.Component.year], from: NSDate() as Date)
        anchorComponents.hour = 0;
        anchorComponents.minute = 0;
        
        guard let anchorDate = calendar.date(from: anchorComponents) else {
            fatalError("*** unable to create a valid date from the given components ***")
        }
        
        guard let activeQuantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned) else {
            fatalError("*** Unable to create a active count type ***")
        }
        
        guard let basalQuantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.basalEnergyBurned) else {
            fatalError("*** Unable to create a basal count type ***")
        }
        
        var lastActiveCount = 0.0;
        var lastBasalCount = 0.0;
        
        // Create the active calorie query
        let activeQuery = HKStatisticsCollectionQuery(quantityType: activeQuantityType,
                                                quantitySamplePredicate: nil,
                                                options: .cumulativeSum,
                                                anchorDate: anchorDate,
                                                intervalComponents: interval as DateComponents)
        
        activeQuery.initialResultsHandler = {
            query, results, error in
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
                fatalError("*** Unable to get active statistics for day ***")
            }
            
            DispatchQueue.main.async {
                if let count = dayStats.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    
                    lastActiveCount = count;
                    listener(lastActiveCount + lastBasalCount)
                }
            }
        }
        
        activeQuery.statisticsUpdateHandler = {
            query, results, collection, error in
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            /*guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
             fatalError("*** Unable to get step statistics for day ***")
             }*/
            
            DispatchQueue.main.async {
                if let count = statsCollection.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    lastActiveCount = count;
                    listener(lastActiveCount + lastBasalCount)
                }
            }
        }
        
        // Create the active calorie query
        let basalQuery = HKStatisticsCollectionQuery(quantityType: basalQuantityType,
                                                      quantitySamplePredicate: nil,
                                                      options: .cumulativeSum,
                                                      anchorDate: anchorDate,
                                                      intervalComponents: interval as DateComponents)
        
        basalQuery.initialResultsHandler = {
            query, results, error in
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
                fatalError("*** Unable to get basal statistics for day ***")
            }
            
            DispatchQueue.main.async {
                if let count = dayStats.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    
                    lastBasalCount = count;
                    listener(lastActiveCount + lastBasalCount)
                }
            }
        }
        
        basalQuery.statisticsUpdateHandler = {
            query, results, collection, error in
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            /*guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
             fatalError("*** Unable to get step statistics for day ***")
             }*/
            
            DispatchQueue.main.async {
                if let count = statsCollection.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    lastBasalCount = count
                    listener(lastBasalCount + lastActiveCount)
                }
            }
        }
        
        healthStore?.execute(activeQuery)
        healthStore?.execute(basalQuery)
    }
    
    func startWatchApp() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .indoor
        
        healthStore?.startWatchApp(with: configuration, completion: { (success, error) in
            if !success {
                print("Cannot start watch app")
            } else {
                print("Start watch app")
            }
        })
    }
    
    func startWorkout() {
        
    }
    
    func writeDebugData() {
        saveHeartRateIntoHealthStore(hr: Double(60 + arc4random() % 120))
        saveStepsIntoHealthStore(steps: Double(arc4random() % 5))
    }
    
    private func saveHeartRateIntoHealthStore(hr:Double) -> Void {
        // Save the user's heart rate into HealthKit.
        let heartRateUnit: HKUnit = HKUnit(from: "count/min")
        let heartRateQuantity: HKQuantity = HKQuantity(unit: heartRateUnit, doubleValue: hr)
        
        let heartRate : HKQuantityType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!
        let nowDate: NSDate = NSDate()
        
        let heartRateSample: HKQuantitySample = HKQuantitySample(type: heartRate
            , quantity: heartRateQuantity, start: nowDate as Date, end: nowDate as Date)
        
        healthStore?.save(heartRateSample) {
            (success, error) in
            
            if success {
                print("heart rate written")
            } else {
                print("heart rate write error \(String(describing: error))")
            }
        }
    }
    
    private func saveStepsIntoHealthStore(steps:Double) -> Void {
        // Save the user's heart rate into HealthKit.
        let stepUnit: HKUnit = HKUnit.count()
        let stepQuantity: HKQuantity = HKQuantity(unit: stepUnit, doubleValue: steps)
        
        let stepType : HKQuantityType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!
        let nowDate: NSDate = NSDate()
        
        let stepSample: HKQuantitySample = HKQuantitySample(type: stepType
            , quantity: stepQuantity, start: nowDate as Date, end: nowDate as Date)
        
        healthStore?.save(stepSample) {
            (success, error) in
            
            if success {
                print("steps written")
            } else {
                print("step write error \(String(describing: error))")
            }
        }
    }
}
