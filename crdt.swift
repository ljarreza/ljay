//
//  crdt.swift
//
//  Created by Louie Jay Arreza Macbook on 21/11/2018.
//  Copyright © 2018 Ljay. All rights reserved.
//

import Foundation

// Mark : -> For use in `LWWElementSet
struct LWWGSet<T: Hashable> {
    
    private var timestamps = [T: Date]()
    
    func lookup(_ item: T) -> Date? {
        return timestamps[item]
    }
   
    func compare(anotherSet: LWWGSet<T>) -> Bool {
        return timestamps.allSatisfy { anotherSet.lookup($0.key) != nil }
    }
 
    mutating func add(_ item: T, timestamp: Date = Date()) {
        if let previousAddTime = lookup(item), previousAddTime >= timestamp {
            return
        }
        timestamps[item] = timestamp
    }
    mutating func merge(anotherSet: LWWGSet<T>) {
        timestamps.merge(anotherSet.timestamps) { (current, new) in max(current, new) }
    }
}

struct LWWElementSet<T: Hashable> {
    private var addSet = LWWGSet<T>()
    private var removeSet = LWWGSet<T>()
    
    func lookup(_ item: T) -> Date? {
        if let addTime = addSet.lookup(item) {
            if let removeTime = removeSet.lookup(item) {
                if (addTime > removeTime) {
                    return addTime
                }
                return nil
            }
            return addTime
        }
        return nil
    }
    
    func compare(anotherSet: LWWElementSet<T>) -> Bool {
        return addSet.compare(anotherSet: anotherSet.addSet) && removeSet.compare(anotherSet: anotherSet.removeSet)
    }
    mutating func add(_ item: T, timestamp: Date = Date()) {
        addSet.add(item, timestamp: timestamp)
    }
    
    mutating func remove(_ item: T, timestamp: Date = Date()) {
        guard lookup(item) != nil else {
            return
        }
        removeSet.add(item, timestamp: timestamp)
    }
    
    mutating func merge(anotherSet: LWWElementSet<T>) {
        addSet.merge(anotherSet: anotherSet.addSet)
        removeSet.merge(anotherSet: anotherSet.removeSet)
    }
    
}

private func testCases() {
    
    /* Timestamps for use in test cases below
       Timestamps are separated 10 mins apart for easy viewing. */
    
    let timestamps = (0...5).map { return Date(timeIntervalSinceReferenceDate: TimeInterval($0 * 10 * 60)) }
    
    // Mark: ->LWW Grow-only set tests
    
    var Set1 = LWWGSet<Int>();
    var Set2 = LWWGSet<Int>();
    
    // Mark: -> ### Single set tests
    Set1.add(1, timestamp: timestamps[0])
    Set1.add(2, timestamp: timestamps[0])
    Set1.add(2, timestamp: timestamps[1])
    Set1.add(3, timestamp: timestamps[1])
    Set1.add(3, timestamp: timestamps[0])
    assert(Set1.lookup(1) == timestamps[0], "Expect timestamp to be returned if item was added")
    assert(Set1.lookup(2) == timestamps[1], "Expect timestamp to be updated if the second add has a higher timestamp")
    assert(Set1.lookup(3) == timestamps[1], "Expect timestamp not to be updated if the second add has a lower timestamp")
    assert(Set1.lookup(4) == nil, "Expect nil if item was not added")
    
    // Mark: ->Set compare tests
    Set2.add(2, timestamp: timestamps[0])
    Set2.add(3, timestamp: timestamps[2])
    
    assert(Set1.compare(anotherSet: Set1) == true, "Expect sets to be subsets of themselves")
    assert(LWWGSet<Int>().compare(anotherSet: Set1) == true, "Expect empty sets to always be subsets")
    assert(Set1.compare(anotherSet: Set2) == false, "Expect set 1 not to be a subset of set 2") // Set 1 has the extra element 1
    assert(Set2.compare(anotherSet: Set1) == true, "Expect set 1 to be a subset of set 2")
    
    // Mark: -> Set compare tests
    Set2.add(4, timestamp: timestamps[0])
    Set1.merge(anotherSet: Set2)
    
    assert(Set1.lookup(1) == timestamps[0], "Expect item not in the other set to be unchanged")
    assert(Set1.lookup(2) == timestamps[1], "Expect item timestamps to be correct - should not be updated if timestamp in the other set was before this set's entry")
    assert(Set1.lookup(3) == timestamps[2], "Expect item timestamps to be correct - should be updated if timestamp in the other set was after this set's entry")
    assert(Set1.lookup(4) == timestamps[0], "Expect item to be added if it was not present")
    assert(Set1.lookup(5) == nil, "Expect nil if item was not in both sets")
    
    // Mark: -> LWW Element set tests
    var lwwESet1 = LWWElementSet<Int>();
    var lwwESet2 = LWWElementSet<Int>();
    
    // Mark: -> Single set tests
    lwwESet1.remove(1, timestamp: timestamps[3])
    assert(lwwESet1.lookup(1) == nil, "Expect item not to be added or removed if the item is not already in the set")
    
    lwwESet1.add(1, timestamp: timestamps[1])
    assert(lwwESet1.lookup(1) == timestamps[1], "Expect timestamp to be returned if item was added")
    
    lwwESet1.add(1, timestamp: timestamps[0])
    assert(lwwESet1.lookup(1) == timestamps[1], "Expect timestamp not to be updated if an item was added with an older timestamp")
    
    lwwESet1.remove(1, timestamp: timestamps[0])
    assert(lwwESet1.lookup(1) == timestamps[1], "Expect item not to be removed if it was added again after")
    
    lwwESet1.remove(1, timestamp: timestamps[1])
    assert(lwwESet1.lookup(1) == nil, "Expect item to be removed if it was removed at exactly the same time as it was added")
    
    lwwESet1.add(1, timestamp: timestamps[2])
    assert(lwwESet1.lookup(1) == timestamps[2], "Expect item to be present if it was added after it was removed")
    
    lwwESet1.remove(1, timestamp: timestamps[3])
    assert(lwwESet1.lookup(1) == nil, "Expect item to be removed if it was removed after it was added")
    
    /* Set compare tests */
    
    // Mark: -> Set up set 2
    lwwESet2.add(1, timestamp: timestamps[0])
    lwwESet2.remove(1, timestamp: timestamps[5])
    lwwESet2.add(2, timestamp: timestamps[1])
    lwwESet2.remove(2, timestamp: timestamps[0])
    
    assert(lwwESet1.compare(anotherSet: lwwESet1) == true, "Expect sets to be subsets of themselves")
    assert(LWWElementSet<Int>().compare(anotherSet: lwwESet1) == true, "Expect empty sets to always be subsets")
    assert(lwwESet1.compare(anotherSet: lwwESet2) == true, "Expect set 1 to be a subset of set 2")
    assert(lwwESet2.compare(anotherSet: lwwESet1) == false, "Expect set 1 not to be a subset of set 2") // Set 2 has the extra element 2
    
    // Mark: -> Set merge tests
    lwwESet1.add(1, timestamp: timestamps[4])
    lwwESet1.merge(anotherSet: lwwESet2)
    
    assert(lwwESet1.lookup(1) == nil, "Expect item that was added in one set and removed later in another to be removed")
    assert(lwwESet1.lookup(2) == timestamps[1], "Expect item to be added if it was not present")
}
