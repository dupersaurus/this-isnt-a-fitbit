//
//  HealthKitInterface.swift
//  metric-stack WatchKit Extension
//
//  Created by Jason DuPertuis on 2/2/19.
//  Copyright © 2019 jdp. All rights reserved.
//

import Foundation
import HealthKit
import WatchKit
import WatchConnectivity

class HealthKitInterface {
    
    private let healthStore: HKHealthStore?
    private let readableTypes: Set<HKQuantityType>?
    
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
    
    private var observerQuery: HKObserverQuery?
    
    private var cachedHeartRate = 0;
    private var cachedStepCount = 0;
    private var cachedCalorieCount = 0;
    
    init() {
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
            self.readableTypes = Set([HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
                                      HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
                                      HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
                                      HKObjectType.quantityType(forIdentifier: .heartRate)!,
                                      HKObjectType.quantityType(forIdentifier: .stepCount)!,
                                      HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!])
            
            self.healthStore?.requestAuthorization(toShare: [], read: self.readableTypes) { (success, error) in
                if success {
                    print("HealthStore set up")
                    //self.observerHeartRateSamples()
                } else {
                    print(error.debugDescription)
                }
            }
        } else {
            self.healthStore = nil
            self.readableTypes = nil
        }
    }
    
    // Adapted from https://stackoverflow.com/questions/30556642/healthkit-fetch-data-between-interval
    
    func observerHeartRateSamples(listener: @escaping (Double) -> Void) {
        let heartRateSampleType = HKObjectType.quantityType(forIdentifier: .heartRate)
        
        if let observerQuery = observerQuery {
            healthStore?.stop(observerQuery)
        }
        
        observerQuery = HKObserverQuery(sampleType: heartRateSampleType!, predicate: nil) { (_, _, error) in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }
            
            self.fetchLatestHeartRateSample { (sample) in
                guard let sample = sample else {
                    print("No HR sample")
                    return
                }
                
                DispatchQueue.main.async {
                    let heartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                    print("Heart Rate Sample: \(Int(heartRate))")
                    listener(heartRate);
                    self.cachedHeartRate = Int(heartRate);
                }
            }
        }
        
        healthStore?.execute(observerQuery!)
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
            
            if results == nil {
                return
            }
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                print("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
                return
            }
            
            guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
                fatalError("*** Unable to get step statistics for day ***")
            }
            
            DispatchQueue.main.async {
                if let count = dayStats.sumQuantity()?.doubleValue(for: HKUnit.count()) {
                    print("Step Sample: \(String(describing: count))")
                    listener(count)
                    self.cachedStepCount = Int(count);
                }
            }
        }
        
        query.statisticsUpdateHandler = {
            query, results, collection, error in
            
            if results == nil {
                return
            }
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                print("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
                return
            }
            
            /*guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
             fatalError("*** Unable to get step statistics for day ***")
             }*/
            
            DispatchQueue.main.async {
                if let count = statsCollection.sumQuantity()?.doubleValue(for: HKUnit.count()) {
                    print("Step Sample: \(String(describing: count))")
                    listener(count)
                    self.cachedStepCount = Int(count);
                }
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
            
            if results == nil {
                return
            }
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                print("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
                return
            }
            
            guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
                fatalError("*** Unable to get active statistics for day ***")
            }
            
            DispatchQueue.main.async {
                if let count = dayStats.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    
                    lastActiveCount = count;
                    listener(lastActiveCount + lastBasalCount)
                    self.cachedStepCount = Int(lastActiveCount) + Int(lastBasalCount);
                }
            }
        }
        
        activeQuery.statisticsUpdateHandler = {
            query, results, collection, error in
            
            if results == nil {
                return
            }
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                print("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
                return
            }
            
            /*guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
             fatalError("*** Unable to get step statistics for day ***")
             }*/
            
            DispatchQueue.main.async {
                if let count = statsCollection.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    lastActiveCount = count;
                    listener(lastActiveCount + lastBasalCount)
                    self.cachedStepCount = Int(lastActiveCount) + Int(lastBasalCount);
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
                print("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
                return
            }
            
            guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
                fatalError("*** Unable to get basal statistics for day ***")
            }
            
            DispatchQueue.main.async {
                if let count = dayStats.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    
                    lastBasalCount = count;
                    listener(lastActiveCount + lastBasalCount)
                    self.cachedStepCount = Int(lastActiveCount) + Int(lastBasalCount);
                }
            }
        }
        
        basalQuery.statisticsUpdateHandler = {
            query, results, collection, error in
            
            guard let statsCollection = results else {
                // Perform proper error handling here
                print("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
                return;
            }
            
            /*guard let dayStats = statsCollection.statistics(for: NSDate() as Date) else {
             fatalError("*** Unable to get step statistics for day ***")
             }*/
            
            DispatchQueue.main.async {
                if let count = statsCollection.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                    print("Step Sample: \(String(describing: count))")
                    lastBasalCount = count
                    listener(lastBasalCount + lastActiveCount)
                    self.cachedStepCount = Int(lastActiveCount) + Int(lastBasalCount);
                }
            }
        }
        
        healthStore?.execute(activeQuery)
        healthStore?.execute(basalQuery)
    }
    
    func startWorkout() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .indoor
        
        do {
            let workout = try HKWorkoutSession(configuration: configuration)
            
            //workout.delegate = interfaceController
            //workout.startActivity()
        }
        catch let error as NSError {
            // Perform proper error handling here...
            fatalError("*** Unable to create the workout session: \(error.localizedDescription) ***")
        }
    }
    
    func getHeartRate() -> Int {
        return cachedHeartRate;
    }
    
    func getSteps() -> Int {
        return cachedStepCount;
    }
    
    func getCalories() -> Int {
        return cachedCalorieCount;
    }
}
