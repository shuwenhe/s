package demo.ownership_ref_flow

func test_ref_flow(int owner) int {
    reader := &owner       
    y := 100               
    other := reader        
    z := y + 1             
    x := *other            
    x                      
}
