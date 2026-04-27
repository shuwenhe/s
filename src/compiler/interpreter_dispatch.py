from __future__ import annotations 

from runtime .host_fs import make_temp_dir as host_make_temp_dir ,read_to_string as host_read_to_string ,write_text_file as host_write_text_file 
from typing import Any ,List ,Tuple 

from runtime .host_intrinsics import (
args as host_args ,
eprintln as host_eprintln ,
get_env as host_get_env ,
println as host_println ,
)
from runtime .host_process import run_argv as host_run_argv 


def dispatch_special_call (interpreter :Any ,name :str ,args :List [Any ])->Tuple [bool ,Any ]:
    if name =="chan_make":
        cap =0 if not args else int (args [0 ])
        return True ,interpreter .chan_make (cap )
    if name =="chan_send":
        if len (args )<2 :
            return True ,False 
        return True ,interpreter .chan_send (args [0 ],args [1 ])
    if name =="chan_recv":
        if not args :
            return True ,("none",None )
        return True ,interpreter .chan_recv (args [0 ])
    if name =="chan_close":
        if args :
            interpreter .chan_close (args [0 ])
        return True ,None 
    if name =="chan_len":
        if not args :
            return True ,0 
        return True ,interpreter .chan_len (args [0 ])
    if name =="go":
        if not args :
            return True ,None 
        fn_name =args [0 ]
        fn_args =args [1 :]
        interpreter .go_spawn (fn_name ,fn_args )
        return True ,None 
    if name =="go_run":
        return True ,interpreter .go_run_one ()
    if name =="go_drain":
        return True ,interpreter .go_drain ()
    if name =="select_recv":
        if not args :
            return True ,("none",None )
        return True ,interpreter .select_recv (args [0 ])
    if name =="select_recv_default":
        if not args :
            return True ,None 
        default_value =None if len (args )<2 else args [1 ]
        return True ,interpreter .select_recv_default (args [0 ],default_value )

    if name in {"ok","err","some"}:
        payload =None if not args else args [0 ]
        return True ,(name ,payload )
    if name =="none":
        return True ,("none",None )
    if name =="println":
        host_println (""if not args else interpreter ._stringify (args [0 ]))
        return True ,None 
    if name =="eprintln":
        host_eprintln (""if not args else interpreter ._stringify (args [0 ]))
        return True ,None 
    if name =="__host_run_shell":
        return True ,host_run_argv (["/bin/sh","-c",""if not args else str (args [0 ])])
    if name =="__host_args":
        return True ,host_args ()
    if name =="__host_get_env":
        value =host_get_env (""if not args else str (args [0 ]))
        if value is None :
            return True ,("none",None )
        return True ,("some",value )
    if name =="__host_read_to_string":
        try :
            return True ,("ok",host_read_to_string (str (args [0 ])))
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
    if name =="__host_write_text_file":
        try :
            host_write_text_file (str (args [0 ]),""if len (args )<2 else str (args [1 ]))
            return True ,("ok",None )
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
    if name =="__host_make_temp_dir":
        try :
            temp_path =host_make_temp_dir (""if not args else str (args [0 ]))
            return True ,("ok",temp_path )
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
    if name =="__host_run_process":
        try :
            code =host_run_argv ([str (arg )for arg in (args [0 ]if args else [])])
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
        if code !=0 :
            return True ,("err",{"message":f"run_process failed with exit code {code }"})
        return True ,("ok",None )
    if name =="__host_run_process1":
        try :
            return True ,host_run_argv ([str (args [0 ])])
        except OSError :
            return True ,1 
    if name =="__host_run_process5":
        try :
            return True ,host_run_argv ([str (arg )for arg in args [:5 ]])
        except OSError :
            return True ,1 
    if name =="__host_run_process_argv":
        command =""if not args else str (args [0 ])
        values =command .split ("<<arg>>")
        if not values or values ==[""]:
            return True ,1 
        try :
            return True ,host_run_argv (values )
        except OSError :
            return True ,1 
    if name =="__host_exit":
        interpreter .explicit_exit_code =int (args [0 ])if args else 0 
        return True ,None 
    return False ,None 


def dispatch_imported_call (interpreter :Any ,imported_path :str ,args :List [Any ])->Tuple [bool ,Any ]:
    if imported_path =="std.env.args":
        return True ,list(interpreter .argv )
    if imported_path =="std.process.exit":
        interpreter .explicit_exit_code =int (args [0 ])if args else 0 
        return True ,None 
    if imported_path =="std.fs.read_to_string":
        try :
            return True ,("ok",host_read_to_string (str (args [0 ])))
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
    if imported_path =="std.fs.write_text_file":
        try :
            host_write_text_file (str (args [0 ]),""if len (args )<2 else str (args [1 ]))
            return True ,("ok",None )
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
    if imported_path =="std.fs.make_temp_dir":
        try :
            temp_path =host_make_temp_dir (""if not args else str (args [0 ]))
            return True ,("ok",temp_path )
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
    if imported_path =="std.process.run_process":
        try :
            code =host_run_argv ([str (arg )for arg in (args [0 ]if args else [])])
        except OSError as exc :
            return True ,("err",{"message":str (exc )})
        if code !=0 :
            return True ,("err",{"message":f"run_process failed with exit code {code }"})
        return True ,("ok",None )
    if imported_path =="std.process.run_process1":
        try :
            return True ,host_run_argv ([str (args [0 ])])
        except OSError :
            return True ,1 
    if imported_path =="std.process.run_process5":
        try :
            return True ,host_run_argv ([str (arg )for arg in args [:5 ]])
        except OSError :
            return True ,1 
    if imported_path =="std.process.run_process_argv":
        command =""if not args else str (args [0 ])
        values =command .split ("<<arg>>")
        if not values or values ==[""]:
            return True ,1 
        try :
            return True ,host_run_argv (values )
        except OSError :
            return True ,1 
    if imported_path =="std.prelude.len":
        return True ,len (args [0 ])if args else 0 
    if imported_path =="std.prelude.to_string":
        return True ,str (args [0 ])if args else ""
    if imported_path =="std.prelude.char_at":
        return True ,str (args [0 ])[int (args [1 ])]
    if imported_path =="std.prelude.slice":
        return True ,str (args [0 ])[int (args [1 ]):int (args [2 ])]
    return False ,None 
