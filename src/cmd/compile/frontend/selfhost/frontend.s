

package cmd.compile.frontend.selfhost

import (
    "cmd.compile.frontend.selfhost.source_scan"
)

func init_frontend() {
    source_scan.scan_sources()
}

type FrontendContext struct {
    
}

func (fc *FrontendContext) analyze() {
    
}
