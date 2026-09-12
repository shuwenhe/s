package ref_liveness_test_driver

use compile.internal.ownership.ref_liveness_analyzer

// ref_liveness_test_driver.s
// Test driver that calls real analyzer functions
// Replaces hardcoded bash results

// Main entry point: run all 6 tests and report results
func main() {
    test_results := vec[string]{
        analyze_test_1(),
        analyze_test_2(),
        analyze_test_3(),
        analyze_test_4(),
        analyze_test_5(),
        analyze_test_6(),
    }
    
    expected := vec[string]{
        "ALLOW",
        "CONFLICT",
        "ALLOW",
        "CONFLICT",
        "CONFLICT",
        "ALLOW",
    }
    
    test_names := vec[string]{
        "straight_last_use",
        "same_place_still_live",
        "branch_all_paths_dead",
        "branch_live_after_join",
        "loop_backedge",
        "disjoint_place",
    }
    
    pass := 0
    fail := 0
    
    for i := 0; i < len(test_results); i = i + 1 {
        result := test_results[i]
        expect := expected[i]
        name := test_names[i]
        
        if result == expect {
            println("✓ " + name + " -> " + result)
            pass = pass + 1
        } else {
            println("✗ " + name + " (expected=" + expect + ", got=" + result + ")")
            fail = fail + 1
        }
    }
    
    println("")
    println("Results: " + to_string(pass) + " PASS, " + to_string(fail) + " FAIL")
    
    if fail > 0 {
        return 1
    }
}

func analyze_test_1() string {
    return analyze_and_report(1)
}

func analyze_test_2() string {
    return analyze_and_report(2)
}

func analyze_test_3() string {
    return analyze_and_report(3)
}

func analyze_test_4() string {
    return analyze_and_report(4)
}

func analyze_test_5() string {
    return analyze_and_report(5)
}

func analyze_test_6() string {
    return analyze_and_report(6)
}
