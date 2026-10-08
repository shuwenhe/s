

package cmd.compile.middlend.selfhost

import (
    "cmd.compile.middlend.selfhost.const_eval"
)

func init_middlend() {
    const_eval.init_const_eval()
}

type MiddlendContext struct {
    
}

func (mc *MiddlendContext) transform() {
    
}
