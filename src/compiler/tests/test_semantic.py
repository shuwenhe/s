from __future__ import annotations 
from typing import Any

from pathlib import Path 
import subprocess 
import sys 
import tempfile 
import unittest 

from compiler .hosted_compiler import run_cli 
from runtime .hosted_command import run_cmd_s 
from compiler .prelude import prelude 
from compiler .parser import parse_source 
from compiler .interpreter import interpreter 
from compiler .semantic import check_source 


fixtures =path (__file__ ).resolve ().parent /"fixtures"


class semantictests (unittest .testcase ):
    def test_check_source_success (self )->None :
        source =(fixtures /"check_ok.s").read_text ()
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_check_source_failure (self )->None :
        source =(fixtures /"check_fail.s").read_text ()
        result =check_source (parse_source (source ))
        self .assertfalse (result .ok )
        self .assertin ("let value expected bool, got int32",[d .message for d in result .diagnostics ])

    def test_cli_check_success (self )->None :
        proc =subprocess .run (
        [sys .executable ,"-m","compiler","check",str (fixtures /"check_ok.s")],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (proc .returncode ,0 ,proc .stderr )
        self .assertin ("ok:",proc .stdout )

    def test_cli_check_failure (self )->None :
        proc =subprocess .run (
        [sys .executable ,"-m","compiler","check",str (fixtures /"check_fail.s")],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (proc .returncode ,1 )
        self .assertin ("error: let value expected bool, got int32",proc .stderr )

    def test_borrow_checker_failure (self )->None :
        source =(fixtures /"borrow_fail.s").read_text ()
        result =check_source (parse_source (source ))
        self .assertfalse (result .ok )
        messages =[d .message for d in result .diagnostics ]
        self .assertin ("cannot mutably borrow value while borrowed",messages )
        self .assertin ("use of moved value text",messages )

    def test_generic_bound_failure (self )->None :
        source =(fixtures /"generic_bound_fail.s").read_text ()
        result =check_source (parse_source (source ))
        self .assertfalse (result .ok )
        messages =[d .message for d in result .diagnostics ]
        self .assertin ("type string does not satisfy bound copy",messages )

    def test_branch_dataflow_failure (self )->None :
        source =(fixtures /"branch_move_fail.s").read_text ()
        result =check_source (parse_source (source ))
        self .assertfalse (result .ok )
        messages =[d .message for d in result .diagnostics ]
        self .assertin ("use of moved value text",messages )

    def test_member_and_trait_method_success (self )->None :
        source =(fixtures /"member_method_sample.s").read_text ()
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_prelude_method_success (self )->None :
        source =(fixtures /"prelude_methods_ok.s").read_text ()
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_method_candidate_conflict (self )->None :
        source =(fixtures /"method_conflict_fail.s").read_text ()
        result =check_source (parse_source (source ))
        self .assertfalse (result .ok )
        messages =[d .message for d in result .diagnostics ]
        self .asserttrue (Any ("multiple method candidates"in message for message in messages ),messages )

    def test_receiver_auto_borrow_success (self )->None :
        source =(fixtures /"receiver_auto_borrow_ok.s").read_text ()
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_prelude_loaded_from_decl (self )->None :
        self .assertequal (prelude .name ,"std.prelude")
        self .assertin ("vec",prelude .types )
        self .assertin ("push",prelude .types ["vec"].methods )
        self .assertin ("len",prelude .traits )
        self .assertequal (prelude .types ["vec"].methods ["push"][0 ].receiver_policy ,"addressable")

    def test_builtin_field_success (self )->None :
        source =(fixtures /"builtin_field_ok.s").read_text ()
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_std_result_option_variant_payloads (self )->None :
        source ="""
package demo.variant_payload

use std.option.option
use std.result.result

func unwrap_or_zero(result[int32, string] value) int32 {
    switch value {
        ok(number) : number,
        err(_) : 0,
    }
}

func unwrap_or_default(option[string] value) string {
    switch value {
        some(text) : text,
        none : "fallback",
    }
}
"""
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_std_use_imported_functions_and_fields (self )->None :
        source ="""
package demo.std

use std.env.args
use std.fs.readtostring
use std.process.runprocess
use std.result.result
use std.vec.vec

func main() int32 {
    var args = args()
    var text =
        switch readtostring("demo.txt") {
            ok(value) : value,
            err(err) : err.message,
        }
    var proc = runprocess(args)
    switch proc {
        ok(_) : 0,
        err(err) : err.message.len(),
    }
}
"""
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_never_branch_from_early_return (self )->None :
        source ="""
package demo.never_branch

use std.result.result

func pick(result[int32, string] value) result[int32, string] {
    var number =
        switch value {
            ok(v) : v,
            err(err) : {
                return err(err)
            },
        }
    ok(number)
}
"""
        result =check_source (parse_source (source ))
        self .asserttrue (result .ok ,[d .message for d in result .diagnostics ])

    def test_cli_build_sum_success (self )->None :
        proc =subprocess .run (
        [sys .executable ,"-m","compiler","build","/app/s/misc/examples/s/sum.s","-o","/tmp/s_sum_test"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (proc .returncode ,0 ,proc .stderr )
        self .assertin ("built:",proc .stdout )

    def test_cli_build_sum_binary_output (self )->None :
        build =subprocess .run (
        [sys .executable ,"-m","compiler","build","/app/s/misc/examples/s/sum.s","-o","/tmp/s_sum_test"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (build .returncode ,0 ,build .stderr )

        run =subprocess .run (
        ["/tmp/s_sum_test"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (run .returncode ,0 ,run .stderr )
        self .assertequal (run .stdout .strip (),"5050")

    def test_hosted_build_sum_binary_output (self )->None :
        code =run_cli (["build","/app/s/misc/examples/s/sum.s","-o","/tmp/s_sum_hosted"])
        self .assertequal (code ,0 )

        run =subprocess .run (
        ["/tmp/s_sum_hosted"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (run .returncode ,0 ,run .stderr )
        self .assertequal (run .stdout .strip (),"5050")

    def test_hosted_build_relative_output_goes_to_app_tmp (self )->None :
        output_path =path ("/app/tmp/s_sum_relative_test")
        if output_path .exists ():
            output_path .unlink ()

        code =run_cli (["build","/app/s/misc/examples/s/sum.s","-o","s_sum_relative_test"])
        self .assertequal (code ,0 )
        self .asserttrue (output_path .exists ())

        run =subprocess .run (
        [str (output_path )],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (run .returncode ,0 ,run .stderr )
        self .assertequal (run .stdout .strip (),"5050")

    def test_hosted_build_vec_push_and_string_concat (self )->None :
        source ="""
package demo.vec_concat

use std.io.println
use std.vec.vec

func main() int {
    var parts = vec[string]()
    parts.push("4");
    parts.push("2");
    println(parts[0] + parts[1]);
    0
}
"""
        with tempfile .temporarydirectory (prefix ="s-semantic-")as tmp :
            source_path =path (tmp )/"vec_concat.s"
            output_path =path (tmp )/"vec_concat_bin"
            source_path .write_text (source )

            code =run_cli (["build",str (source_path ),"-o",str (output_path )])
            self .assertequal (code ,0 )

            run =subprocess .run (
            [str (output_path )],
            cwd ="/app/s/src",
            capture_output =True ,
            text =True ,
            check =False ,
            )
            self .assertequal (run .returncode ,0 ,run .stderr )
            self .assertequal (run .stdout .strip (),"42")

    def test_hosted_build_match_while_vec_index (self )->None :
        source ="""
package demo.match_while_vec

use std.io.println
use std.option.option
use std.vec.vec

func pick(option[string] value) string {
    return switch value {
        some(text) : text,
        none : "2",
    }
}

func tail() option[string] {
    return some("2")
}

func main() int {
    var parts = vec[string]()
    var index = 0
    while index <= 0 {
        parts.push("4");
        index++;
    }
    var extra = pick(tail())
    parts.push(extra);
    println(parts[0] + parts[1]);
    0
}
"""
        with tempfile .temporarydirectory (prefix ="s-semantic-")as tmp :
            source_path =path (tmp )/"match_while_vec.s"
            output_path =path (tmp )/"match_while_vec_bin"
            source_path .write_text (source )

            code =run_cli (["build",str (source_path ),"-o",str (output_path )])
            self .assertequal (code ,0 )

            run =subprocess .run (
            [str (output_path )],
            cwd ="/app/s/src",
            capture_output =True ,
            text =True ,
            check =False ,
            )
            self .assertequal (run .returncode ,0 ,run .stderr )
            self .assertequal (run .stdout .strip (),"42")

    def test_hosted_build_s_native_runner_binary_output (self )->None :
        code =run_cli (["build","/app/s/src/runtime/runner.s","-o","/tmp/s_native_hosted"])
        self .assertequal (code ,0 )
        binary =path ("/tmp/s_native_hosted").read_bytes ()
        self .asserttrue (binary .startswith (b"\x7felf"))

        rebuild =subprocess .run (
        ["/tmp/s_native_hosted","build","/app/s/src/runtime/runner.s","-o","/tmp/s_native_self_hosted"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (rebuild .returncode ,0 ,rebuild .stderr )
        self .asserttrue (path ("/tmp/s_native_self_hosted").read_bytes ().startswith (b"\x7felf"))

        build =subprocess .run (
        ["/tmp/s_native_self_hosted","build","/app/s/misc/examples/s/sum.s","-o","/tmp/s_sum_via_native_hosted"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (build .returncode ,0 ,build .stderr )

        run =subprocess .run (
        ["/tmp/s_sum_via_native_hosted"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (run .returncode ,0 ,run .stderr )
        self .assertequal (run .stdout .strip (),"5050")

    def test_cmd_s_hosted_build_sum_binary_output (self )->None :
        result =run_cmd_s (["build","/app/s/misc/examples/s/sum.s","-o","/tmp/s_sum_cmd_s"])
        self .assertequal (result .exit_code ,0 )

        run =subprocess .run (
        ["/tmp/s_sum_cmd_s"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (run .returncode ,0 ,run .stderr )
        self .assertequal (run .stdout .strip (),"5050")

    def test_native_runner_build_sum_binary_output (self )->None :
        build_runner =subprocess .run (
        ["/app/s/misc/scripts/build_native_runner.sh","/tmp/s_native_test"],
        cwd ="/app",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (build_runner .returncode ,0 ,build_runner .stderr )

        build =subprocess .run (
        ["/tmp/s_native_test","build","/app/s/misc/examples/s/sum.s","-o","/tmp/s_sum_native_test"],
        cwd ="/app",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (build .returncode ,0 ,build .stderr )

        run =subprocess .run (
        ["/tmp/s_sum_native_test"],
        cwd ="/app/s/src",
        capture_output =True ,
        text =True ,
        check =False ,
        )
        self .assertequal (run .returncode ,0 ,run .stderr )
        self .assertequal (run .stdout .strip (),"5050")

    def test_s_native_runner_interprets_int_literal_shape (self )->None :
        runner =interpreter (parse_source (path ("/app/s/src/runtime/runner.s").read_text ()))
        result =runner .call_function (
        "compilemessageforsource",
        [
        "package demo.literal\n\nuse std.io.println\n\nfunc main() int {\n    println(42);\n    0\n}\n"
        ],
        )
        self .assertequal (result ,("some","42\n"))

    def test_s_native_runner_encodes_extended_ascii (self )->None :
        runner =interpreter (parse_source (path ("/app/s/src/runtime/runner.s").read_text ()))
        result =runner .call_function ("encodebytes",["@[]{}~"])
        self .assertequal (result ,"64, 91, 93, 123, 125, 126")