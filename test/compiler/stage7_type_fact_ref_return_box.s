package stage7_type_fact_ref_return_box
func helper(ref x) ref { return x; }
func main() int {
    b := box(1);
    r := &b;
    rr := helper(r);
    return *rr;
}
