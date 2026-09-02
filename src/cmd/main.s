package main

func main() int {
    rt_init(0x10000000)
    
    bootstrap_init()
    if bootstrap_check_integrity() == 0 {
        rt_panic("Bootstrap chain integrity check failed")
    }
    
    toolchain_init("x86_64-linux")
    
    regression_data := regression_suite_new()
    frontend := setup_frontend_tests()
    regression_add_suite(&regression_data, frontend)
    
    backend := setup_backend_tests()
    regression_add_suite(&regression_data, backend)
    
    integration := setup_integration_tests()
    regression_add_suite(&regression_data, integration)
    
    total_passed := regression_run_all(&regression_data)
    regression_print_results(&regression_data)
    
    if total_passed > 0 {
        rt_exit(0)
    } else {
        rt_exit(1)
    }
    
    0
}
