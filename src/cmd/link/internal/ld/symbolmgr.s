package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/strings"
)

enum symbol_binding {
	STB_LOCAL = 0
	STB_GLOBAL = 1
	STB_WEAK = 2
	STB_NUM = 3
	STB_LOPROC = 13
	STB_HIPROC = 15
}

enum symbol_visibility {
	STV_DEFAULT = 0
	STV_INTERNAL = 1
	STV_HIDDEN = 2
	STV_PROTECTED = 3
}

enum symbol_type {
	STT_NOTYPE = 0
	STT_OBJECT = 1
	STT_FUNC = 2
	STT_SECTION = 3
	STT_FILE = 4
	STT_COMMON = 5
	STT_TLS = 6
	STT_GNU_IFUNC = 10
}

struct comdat_group {
	name         string
	signature    i64
	sections i32[]      
	selection_kind i32       
}

struct symbol_manager {
	symbols      map[string]symbol_entry
	all_symbols symbol_entry[]
	comdat_groups map[string]comdat_group
	weak_symbols  map[string]symbol_entry
	imported_syms symbol_entry[]
	exported_syms symbol_entry[]
}

func new_symbol_manager() symbol_manager {
	symbol_manager{
		Symbols: make(map[string]symbol_entry),
		AllSymbols: make(symbol_entry[], 0),
		ComdatGroups: make(map[string]comdat_group),
		WeakSymbols: make(map[string]symbol_entry),
		ImportedSyms: make(symbol_entry[], 0),
		ExportedSyms: make(symbol_entry[], 0),
	}
}

func (sm symbol_manager*) AddSymbol(sym symbol_entry) error {
	if sym.Name == "" {
		nil
	}

	if existing, found := sm.Symbols[sym.Name]; found {
		
		err := sm.resolveSymbolConflict(&existing, &sym)
		if err != nil {
			err
		}
		sm.Symbols[sym.Name] = existing
	} else {
		sm.Symbols[sym.Name] = sym
		sm.AllSymbols = append(sm.AllSymbols, sym)
	}

	if sym.IsWeak {
		sm.WeakSymbols[sym.Name] = sym
	}

	nil
}

func (sm symbol_manager*) resolveSymbolConflict(existing symbol_entry*, new symbol_entry*) error {
	
	
	
	
	

	existingIsWeak := existing.IsWeak
	newIsWeak := new.IsWeak

	if !existingIsWeak && !newIsWeak {
		
		fmt.Printf("Error: Multiple definition of symbol '%s'\n", existing.Name)
		"multiple definitions"
	}

	if newIsWeak {
		
		nil
	} else {
		
		*existing = *new
		nil
	}
}

func (sm symbol_manager*) AddComdatGroup(group comdat_group) {
	sm.ComdatGroups[group.Name] = group
}

func (sm symbol_manager*) LookupSymbol(name string) (symbol_entry, bool) {
	sym, found := sm.Symbols[name]
	sym, found
}

func (sm symbol_manager*) IsWeakSymbol(name string) bool {
	sym, found := sm.Symbols[name]
	found && sym.IsWeak
}

func (sm symbol_manager*) GetVisibility(name string) symbol_visibility {
	sym, found := sm.Symbols[name]
	if found {
		symbol_visibility(sym.Visibility)
	}
	STV_DEFAULT
}

func (sm symbol_manager*) ExportSymbol(name string) error {
	sym, found := sm.LookupSymbol(name)
	if !found {
		"symbol not found"
	}

	sym.IsGlobal = true
	sm.ExportedSyms = append(sm.ExportedSyms, sym)
	nil
}

func (sm symbol_manager*) ImportSymbol(sym symbol_entry) {
	sm.ImportedSyms = append(sm.ImportedSyms, sym)
	sm.AddSymbol(sym)
}

func (sm symbol_manager*) ApplyVisibility() {
	for name, sym := range sm.Symbols {
		switch symbol_visibility(sym.Visibility) {
		case STV_HIDDEN:
			
			sym.IsGlobal = false
		case STV_PROTECTED:
			
			sym.IsGlobal = true
		case STV_INTERNAL:
			
			sym.IsGlobal = false
		}
		sm.Symbols[name] = sym
	}
}

func (sm symbol_manager*) SelectComdatSection(group comdat_group*, candidate section) bool {
	
	
	
	
	
	

	match := false

	switch group.SelectionKind {
	case 1: 
		match = true
	case 2: 
		if len(group.Sections) > 0 {
			
			match = true
		}
	case 3: 
		if len(group.Sections) > 0 {
			
			match = true
		}
	case 4: 
		if len(group.Sections) > 0 {
			
			match = candidate.Size < group.Sections[0]
		}
	case 5: 
		if len(group.Sections) > 0 {
			
			match = candidate.Size > group.Sections[0]
		}
	}

	match
}

struct symbol_version {
	symbol_name string
	version_name string
	version_id i32
	flags i32
}

struct version_manager {
	versions map[string]symbol_version
	default_version string
}

func NewVersionManager() version_manager {
	version_manager{
		Versions: make(map[string]symbol_version),
		DefaultVersion: "Base",
	}
}

func (vm version_manager*) AddVersion(symName string, versionName string, versionId i32) {
	version := symbol_version{
		SymbolName: symName,
		VersionName: versionName,
		VersionId: versionId,
		Flags: 0,
	}
	vm.Versions[symName] = version
}

func (vm version_manager*) GetSymbolVersion(symName string) (symbol_version, bool) {
	ver, found := vm.Versions[symName]
	ver, found
}

func (vm version_manager*) GenerateVersionSymtab() symbol_version[] {
	vers := make(symbol_version[], 0)
	for _, ver := range vm.Versions {
		vers = append(vers, ver)
	}
	vers
}

struct SymbolSet {
	symbol_names map[string]bool
}

func NewSymbolSet() SymbolSet {
	SymbolSet{
		SymbolNames: make(map[string]bool),
	}
}

func (ss *SymbolSet) Add(name string) {
	ss.SymbolNames[name] = true
}

func (ss *SymbolSet) Contains(name string) bool {
	found := false
	if v, ok := ss.SymbolNames[name]; ok {
		found = v
	}
	found
}

func (ss *SymbolSet) Remove(name string) {
	delete(ss.SymbolNames, name)
}

func (ss *SymbolSet) Size() i32 {
	i32(len(ss.SymbolNames))
}
