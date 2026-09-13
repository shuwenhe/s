package backend
func demo_add_two_numbers() string {
    pipeline := make_compiler_pipeline()
    asm := ".intel_syntax noprefix\n"
    asm = asm + ".section\t.text\n"
    asm = asm + ".globl add_numbers\n"
    asm = asm + ".type add_numbers, @function\n"
    asm = asm + "add_numbers:\n"
    asm = asm + "\tpush\trbp\n"
    asm = asm + "\tmov\trsp, rbp\n"
    asm = asm + "\tadd\trsi, rdi\n"
    asm = asm + "\tmov\trax, rdi\n"
    asm = asm + "\tpop\trbp\n"
    asm = asm + "\tret\n"
    asm
}

func demo_fibonacci(int n) string {
    pipeline := make_compiler_pipeline()
    asm := ".intel_syntax noprefix\n"
    asm = asm + ".section\t.text\n"
    asm = asm + ".globl fibonacci\n"
    asm = asm + ".type fibonacci, @function\n"
    asm = asm + "fibonacci:\n"
    asm = asm + "\tpush\trbp\n"
    asm = asm + "\tmov\trsp, rbp\n"
    asm = asm + "\tpush\trbx\n"
    asm = asm + "\tpush\tr12\n"
    asm = asm + "\tmov\trax, rdi\n"
    asm = asm + "\tcmp\trax, 2\n"
    asm = asm + "\tjl\t.fib_base\n"
    asm = asm + "\tmov\trbx, rax\n"
    asm = asm + "\tdec\trax\n"
    asm = asm + "\tcall\tfibonacci\n"
    asm = asm + "\tmov\tr12, rax\n"
    asm = asm + "\tmov\trax, rbx\n"
    asm = asm + "\tsub\trax, 2\n"
    asm = asm + "\tcall\tfibonacci\n"
    asm = asm + "\tadd\trax, r12\n"
    asm = asm + "\tjmp\t.fib_end\n"
    asm = asm + ".fib_base:\n"
    asm = asm + "\tmov\trax, 1\n"
    asm = asm + ".fib_end:\n"
    asm = asm + "\tpop\tr12\n"
    asm = asm + "\tpop\trbx\n"
    asm = asm + "\tpop\trbp\n"
    asm = asm + "\tret\n"
    asm
}

func demo_factorial() string {
    pipeline := make_compiler_pipeline()
    asm := ".intel_syntax noprefix\n"
    asm = asm + ".section\t.text\n"
    asm = asm + ".globl factorial\n"
    asm = asm + ".type factorial, @function\n"
    asm = asm + "factorial:\n"
    asm = asm + "\tpush\trbp\n"
    asm = asm + "\tmov\trsp, rbp\n"
    asm = asm + "\tmov\trax, 1\n"
    asm = asm + ".fact_loop:\n"
    asm = asm + "\tcmp\trdi, 1\n"
    asm = asm + "\tjle\t.fact_end\n"
    asm = asm + "\timul\trax, rdi\n"
    asm = asm + "\tdec\trdi\n"
    asm = asm + "\tjmp\t.fact_loop\n"
    asm = asm + ".fact_end:\n"
    asm = asm + "\tpop\trbp\n"
    asm = asm + "\tret\n"
    asm
}

func demo_array_sum() string {
    pipeline := make_compiler_pipeline()
    asm := ".intel_syntax noprefix\n"
    asm = asm + ".section\t.text\n"
    asm = asm + ".globl array_sum\n"
    asm = asm + ".type array_sum, @function\n"
    asm = asm + "array_sum:\n"
    asm = asm + "\tpush\trbp\n"
    asm = asm + "\tmov\trsp, rbp\n"
    asm = asm + "\txor\trax, rax\n"
    asm = asm + ".sum_loop:\n"
    asm = asm + "\tcmp\trsi, 0\n"
    asm = asm + "\tjle\t.sum_end\n"
    asm = asm + "\tadd\trax, [rdi]\n"
    asm = asm + "\tadd\trdi, 8\n"
    asm = asm + "\tdec\trsi\n"
    asm = asm + "\tjmp\t.sum_loop\n"
    asm = asm + ".sum_end:\n"
    asm = asm + "\tpop\trbp\n"
    asm = asm + "\tret\n"
    asm
}

func demo_hello_world() string {
    pipeline := make_compiler_pipeline()
    asm := ".intel_syntax noprefix\n"
    asm = asm + ".section\t.data\n"
    asm = asm + "msg:\n"
    asm = asm + "\t.asciz \"Hello, World!\"\n"
    asm = asm + ".section\t.text\n"
    asm = asm + ".globl main\n"
    asm = asm + ".type main, @function\n"
    asm = asm + "main:\n"
    asm = asm + "\tpush\trbp\n"
    asm = asm + "\tmov\trsp, rbp\n"
    asm = asm + "\tlea\trdi, [rip+msg]\n"
    asm = asm + "\tcall\tprintf\n"
    asm = asm + "\txor\trax, rax\n"
    asm = asm + "\tpop\trbp\n"
    asm = asm + "\tret\n"
    asm
}
