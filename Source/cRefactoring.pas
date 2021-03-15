{-----------------------------------------------------------------------------
 Unit Name: cRefactoring
 Author:    Kiriakos Vlahos
 Date:      03-Jul-2005
 Purpose:   Refactoring support
 History:
-----------------------------------------------------------------------------}

unit cRefactoring;

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.Contnrs,
  cPythonSourceScanner;

type
  {
     Our own limited refactoring implementation
  }

  ERefactoringException = class(Exception);

  TPyScripterRefactor = class
  private
    fPythonScanner : TPythonScanner;
    fProxyModules : TStringList;
    fParsedModules : TStringList;
    fImportResolverCache : TStringList;
    fGetTypeCache : TStringList;
    fSpecialPackages : TStringList;
    fSourceScanners : TInterfaceList;
    fCancelled: Boolean;
    fProcessingLock: TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ClearParsedModules;
    procedure ClearProxyModules;
    function InitializeQuery : Boolean;
    procedure FinalizeQuery;
    procedure Cancel;
    function GetSource(const FName : string; var Source : string): Boolean;
    function GetParsedModule(const ModuleName : string; const PythonPath: array of string) : TParsedModule;
    { given the coordates to a reference, tries to find the
        definition of that reference - Returns TCodeElement, TVariable or nil}
    function FindDefinitionByCoordinates(const Filename : string; Line, Col: integer;
      var ErrMsg : string; Initialize : Boolean = True) : TBaseCodeElement;
    { given the coords of a function, class, method or variable
        returns a list of references to it. }
    procedure FindReferencesByCoordinates(Filename : string; Line, Col: integer;
      var ErrMsg : string; List : TStringList);
    function FindUnDottedDefinition(const Ident : string; ParsedModule : TParsedModule;
      Scope : TCodeElement; var ErrMsg : string) : TBaseCodeElement;
    function FindDottedIdentInScope(const DottedIdent : string; Scope : TCodeElement;
      var ErrMsg: string) : TBaseCodeElement;
    function FindDottedDefinition(const DottedIdent : string; ParsedModule : TParsedModule;
      Scope : TCodeElement; var ErrMsg : string) : TBaseCodeElement;
    function ResolveModuleImport(ModuleImport : TModuleImport): TParsedModule; overload;
    function ResolveModuleImport(const ModuleName,
        SourceFileName : string; PrefixDotCount : integer = 0) : TParsedModule; overload;
    function ResolveImportedName(const Ident: string; ModuleImport: TModuleImport;
      var ErrMsg: string): TBaseCodeElement;
    function GetVarType(Variable : TVariable; var ErrMsg : string) : TCodeElement;
    procedure FindReferences(CE : TBaseCodeElement; var ErrMsg : string;
      List : TStringList);
    procedure FindReferencesInModule(CE : TBaseCodeElement; Module : TParsedModule;
      CodeBlock: TCodeBlock; var ErrMsg : string; List : TStringList);
    procedure FindReferencesGlobally(CE : TBaseCodeElement; var ErrMsg : string;
      List : TStringList);
    function GetBuiltInName(AName : string) : TCodeElement;
    function GetFuncReturnType(FunctionCE: TParsedFunction; var ErrMsg: string): TCodeElement;
  end;

var
  PyScripterRefactor : TPyScripterRefactor;

Const
  FilePosInfoFormat : string = '%s (%d:%d)';
  FilePosInfoRegExpr : string = '(.+) \((\d+):(\d+)\)$';

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  System.SyncObjs,
  PythonEngine,
  VarPyth,
  JclStrings,
  JvGnugettext,
  StringResources,
  uEditAppIntfs,
  uCommonFunctions,
  cPyBaseDebugger,
  cPyScripterSettings,
  cPyDebugger,
  cPyControl,
  cInternalPython,
  cSSHSupport;

{ TPyScripterRefactor }

constructor TPyScripterRefactor.Create;
begin
  inherited;
  fPythonScanner := TPythonScanner.Create;

  fParsedModules := TStringList.Create;
  fParsedModules.CaseSensitive := True;
  fParsedModules.Sorted := True;
  fParsedModules.Duplicates := dupError;

  fProxyModules := TStringList.Create;
  fProxyModules.CaseSensitive := True;
  fProxyModules.Sorted := True;
  fProxyModules.Duplicates := dupError;

  fImportResolverCache := TStringList.Create;
  fImportResolverCache.CaseSensitive := True;
  fImportResolverCache.Sorted := True;
  fImportResolverCache.Duplicates := dupError;

  fGetTypeCache := TStringList.Create;
  fGetTypeCache.CaseSensitive := True;
  fGetTypeCache.Sorted := True;
  fGetTypeCache.Duplicates := dupError;

  fSpecialPackages := TStringList.Create;
  fSpecialPackages.CaseSensitive := true;

  fSourceScanners := TInterfaceList.Create;

  fProcessingLock.Initialize;
end;

procedure TPyScripterRefactor.FinalizeQuery;
begin
  fSourceScanners.Clear;
  fProcessingLock.Leave;;
end;

function TPyScripterRefactor.FindDefinitionByCoordinates(const Filename: string; Line,
  Col: integer; var ErrMsg : string; Initialize : Boolean = True): TBaseCodeElement;
var
  DottedIdent, LineS : string;
  ParsedModule : TParsedModule;
  Scope : TCodeElement;
  PythonPathAdder : IInterface;
  Server, Path : string;
begin
  Result := nil;
  if Initialize then begin
    if not InitializeQuery then begin
      ErrMsg := _(SRefactoryEngineBusy);
      Exit;
    end;
    // Add the file path to the Python path - Will be automatically removed
    if not TSSHFileName.Parse(FileName, Server, Path) then
      Path := ExtractFileDir(FileName)
    else
      Path := '';
    if Length(Path) > 1 then
    begin
      PythonPathAdder :=  GI_PyControl.AddPathToInternalPythonPath(Path);
    end;
  end;

  // GetParsedModule
  ParsedModule := GetParsedModule(FileName, []);
  if not Assigned(ParsedModule) then begin
    ErrMsg := Format(_(SCouldNotLoadModule), [FileName]);
    if Initialize then FinalizeQuery;
    Exit;
  end;

  // Extract the identifier
  LineS := GetNthLine(ParsedModule.Source, Line);
  DottedIdent := GetWordAtPos(LineS, Col, IdentChars+['.'], True, False, True);
  DottedIdent := DottedIdent + GetWordAtPos(LineS, Col + 1, IdentChars, False, True);

  if DottedIdent = '' then begin
    ErrMsg := _(SNoIdentifier);
    if Initialize then FinalizeQuery;
    Exit;
 end;

  // Find scope for line
  Scope := ParsedModule.GetScopeForLine(Line);
  if not assigned(Scope) then
    ErrMsg := _(SCouldNotFindScope)
  else if (DottedIdent = Scope.Name) and (Scope.CodeBlock.StartLine = Line) then
    Result := Scope
  else
    // Find identifier in the module and scope
    Result := FindDottedDefinition(DottedIdent, ParsedModule, Scope, ErrMsg);

  if Initialize then FinalizeQuery;
 end;

destructor TPyScripterRefactor.Destroy;
begin
  Cancel;
  fProcessingLock.Enter;
  try
    fPythonScanner.Free;

    ClearParsedModules;
    fParsedModules.Free;

    ClearProxyModules;
    fProxyModules.Free;

    fImportResolverCache.Free;
    fGetTypeCache.Free;

    fSpecialPackages.Free;
    fSourceScanners.Free;
  finally
    fProcessingLock.Leave;
  end;
  fProcessingLock.Destroy;
  inherited;
end;

function TPyScripterRefactor.GetParsedModule(const ModuleName: string;
  const PythonPath: array of string): TParsedModule;
{
   ModuleName can be either
     - a fully qualified file name
     - a possibly dotted module name existing in the Python path
}
{ TODO : Deal Source residing in zip file etc. }

  function GetProxyFromSysModule(Name: string): TParsedModule;
  var
    Py: IPyEngineAndGIL;
    InSysModules : Boolean;
    Index : integer;
  begin
    Result := nil;
    Py := SafePyEngine;
    InSysModules := SysModule.modules.__contains__(Name);
    if InSysModules and VarIsPythonModule(SysModule.modules.__getitem__(Name)) then begin
      // If the source file does not exist look at sys.modules to see whether it
      // is available in the interpreter.  If yes then create a proxy module
      Index := fProxyModules.IndexOf(Name);
      if Index < 0 then begin
        Index := fProxyModules.AddObject(Name,
          TModuleProxy.CreateFromModule(SysModule.modules.__getitem__(Name),
          PyControl.InternalInterpreter));
        Result := fProxyModules.Objects[Index] as TParsedModule;
      end else
        Result := fProxyModules.Objects[Index] as TParsedModule;
    end;
  end;

var
  Index, SpecialPackagesIndex : integer;
  FName : string;
  ModuleSource  : string;
  DottedModuleName : string;
  ParsedModule : TParsedModule;
  Editor : IEditor;
  SourceScanner : IAsyncSourceScanner;
  FAge : TDateTime;
begin
  Result := nil;

  if fCancelled then Exit;

  if FileExists(ModuleName) then begin
    FName := ModuleName;
    DottedModuleName := FileNameToModuleName(FName);
  end else begin
    FName := '';
    DottedModuleName := ModuleName;
  end;

  // If module name in special packages then import module
  fSpecialPackages.CommaText := PyIDEOptions.SpecialPackages;
  SpecialPackagesIndex := fSpecialPackages.IndexOf(DottedModuleName);

  if SpecialPackagesIndex >= 0 then
    // only import if it is not available
    try
      var SuppressOutput := GI_PyInterpreter.OutputSuppressor; // Do not show errors
      var Py := SafePyEngine;
      if SysModule.modules.__contains__(DottedModuleName) then
      else
        Import(AnsiString(DottedModuleName));
    except
      SpecialPackagesIndex := -1;
    end;

  // if it is an open file then get the parsed module directly
  if SpecialPackagesIndex < 0 then begin
    // Check whether it is an unsaved file
    Editor := GI_EditorFactory.GetEditorByNameOrTitle(DottedModuleName);
    // Find the source file
    if FName = '' then begin  // No filename was provided
      var Py := SafePyEngine;
      var PyPath: Variant;
      if Length(PythonPath) > 0 then
      begin
        PyPath := NewPythonList;
        for var S In PythonPath do
          PyPath.append(S)
      end
      else
        PyPath := None;

      var FNameVar: Variant := TPyInternalInterpreter(PyControl.InternalInterpreter).
        PyInteractiveInterpreter.findModuleOrPackage(DottedModuleName, PyPath);
      if not VarIsNone(FNameVar) then
         FName := FNameVar;
    end;
    if not Assigned(Editor) and (FName <> '') then
      Editor := GI_EditorFactory.GetEditorByName(FName);

    if Assigned(Editor) and Editor.HasPythonFile then
    begin
      SourceScanner := Editor.SourceScanner as IAsyncSourceScanner;
      if Assigned(SourceScanner) then
      begin
        fSourceScanners.Add(SourceScanner);
        Result := SourceScanner.ParsedModule;
      end;
    end;
  end;

  // Next try to find the source
  if (Result = nil) and (FName <> '') and FileIsPythonSource(FName) then
  begin
    DottedModuleName := FileNameToModuleName(FName);
    Index := fParsedModules.IndexOf(DottedModuleName);
    if (Index >= 0) then begin
      // check whether we have the latest version
      Result := fParsedModules.Objects[Index] as TParsedModule;
      if FileAge(FName, FAge) and not SameDateTime(FAge, Result.FileAge) then begin
        fParsedModules.Delete(Index);
        FreeAndNil(Result);
      end;
    end;
    if (Result = nil) and GetSource(FName, ModuleSource) then begin
      ParsedModule := TParsedModule.Create(FName, ModuleSource);
      ParsedModule.Name := DottedModuleName;
      if FileAge(FName, FAge) then ParsedModule.FileAge := FAge;
      fPythonScanner.ScanModule(ParsedModule);
      fParsedModules.AddObject(DottedModuleName, ParsedModule);
      Result := ParsedModule;
    end;
  end;

  // Last effort.  Search in sys.modules
  // Special modules should already be there
  if Result = nil then begin
    if DottedModuleName = '__main__' then
      Result := PyControl.ActiveInterpreter.MainModule
    else
      Result := GetProxyFromSysModule(DottedModuleName);
  end;
end;

function TPyScripterRefactor.GetSource(const FName: string;
  var Source: string): Boolean;
var
  Editor : IEditor;
  S: string;
begin
  Result := False;
  Editor := GI_EditorFactory.GetEditorByNameOrTitle(FName);
  if Assigned(Editor) then begin
    TThread.Synchronize(nil, procedure
    begin
      S := Editor.SynEdit.Text;
    end);
    Source := S;
    Result := True;
  end;
  if not Result then begin
    if not FileExists(FName) then
      Exit;
    try
      Source := FileToStr(FName);
      Result := True;
    except
      // We cannot open the file for some reason
      Result := False;
    end;
  end;
end;

procedure TPyScripterRefactor.Cancel;
begin
  fCancelled := True;
end;

procedure TPyScripterRefactor.ClearParsedModules;
var
  i : integer;
begin
  for i := 0 to fParsedModules.Count - 1 do
    fParsedModules.Objects[i].Free;
  fParsedModules.Clear;
end;

procedure TPyScripterRefactor.ClearProxyModules;
var
  i : integer;
begin
  fProcessingLock.Enter;
  try
    for i := 0 to fProxyModules.Count - 1 do
      fProxyModules.Objects[i].Free;
    fProxyModules.Clear;
  finally
    fProcessingLock.Leave;
  end;
end;

function TPyScripterRefactor.FindDottedDefinition(const DottedIdent: string;
  ParsedModule : TParsedModule; Scope: TCodeElement; var ErrMsg: string): TBaseCodeElement;
{
  Look for a dotted identifier in a given CodeElement (scope) of a ParsedModule
  The function first finds the first part of the dotted definition and then
  calls the recursive function FindDottedIdentInScope
}
Var
  Prefix, Suffix : string;
  Def : TBaseCodeElement;
begin
  Result := nil;
  Suffix := DottedIdent;
  //  Deal with relative imports
  while (Suffix <> '') and (Suffix[1] = '.') do
    Delete(Suffix, 1, 1);

  if Suffix = '' then Exit;

  Prefix := StrToken(Suffix, '.');
  Def := FindUnDottedDefinition(Prefix, ParsedModule, Scope, ErrMsg);

  if Assigned(Def) then begin
    if Suffix <> '' then begin
      if Def.ClassType = TVariable then
        Def := GetVarType(TVariable(Def), ErrMsg);
      if Assigned(Def) then
        Result := FindDottedIdentInScope(Suffix, Def as TCodeElement, ErrMsg);
    end else
      Result := Def;
  end else
    ErrMsg := Format(_(SCouldNotFindIdentInScope),
          [DottedIdent, Scope.Name]);
end;

function TPyScripterRefactor.FindUnDottedDefinition(const Ident: string;
  ParsedModule : TParsedModule; Scope: TCodeElement; var ErrMsg: string): TBaseCodeElement;
{
  Look for an undotted (root) identifier in a given CodeElement (scope)
  of a ParsedModule
  First it checks whether it is an expression
  Second it checks the Scope and Parent scopes
  Then it checks the builtin module
  Finally it looks for implicitely imported modules and from * imports
}
Var
  NameSpace : TStringList;
  Index: integer;
  CodeElement : TCodeElement;
  Identifier : string;
  VarAtts: TVariableAttributes;
begin
  Result := nil;
  // Special case for self or cls
  if (Ident = 'self') or (Ident = 'cls') then begin
    Result := Scope;
    while not (Result is TParsedClass) and Assigned(TCodeElement(Result).Parent) do
      Result := TCodeElement(Result).Parent;
    if not (Result is TParsedClass) then begin
      Result := nil;
      ErrMsg := _(SSelfOutsideClassScope);
    end;
    Exit;
  end;

  Identifier := Ident;
  // First check for brackets
  if Ident.IndexOfAny([')', ']', '}']) >= 0 then begin
    Identifier := GetExpressionType(Ident, VarAtts);
    if Identifier = ''  then  begin
      ErrMsg := Format(_(SCouldNotInferType), [Ident]);
      Exit;
    end;
  end;

  NameSpace := TStringList.Create;
  NameSpace.CaseSensitive := True;
  try
    // Second check the Scope and Parent scopes
    CodeElement := Scope;
    while Assigned(CodeElement) do begin
      NameSpace.Clear;
      CodeElement.GetNameSpace(NameSpace);
      Index := NameSpace.IndexOf(Identifier);
      if Index >= 0 then begin
        Result := NameSpace.Objects[Index] as TBaseCodeElement;
        break;
      end;
      CodeElement := CodeElement.Parent as TCodeElement;
      while Assigned(CodeElement) and (CodeElement is TParsedClass) do
        // Class namespace not visible to class functions and nested classes  #672
        CodeElement := CodeElement.Parent as TCodeElement;
    end;
  finally
    NameSpace.Free;
  end;

  // then check the builtin module
  if not Assigned(Result) then
    Result := GetBuiltInName(Identifier);

  if Assigned(Result) and (Result is TVariable)
    and (TVariable(Result).Parent is TModuleImport)
  then
    // Resolve further
    Result := ResolveImportedName(TVariable(Result).RealName,
      TModuleImport(TVariable(Result).Parent), ErrMsg);

  if Assigned(Result) and (Result is TModuleImport) then
    Result := ResolveModuleImport(TModuleImport(Result));

  if not Assigned(Result) then
    ErrMsg := Format(_(SCouldNotFindIdent),
      [Identifier, ParsedModule.Name]);
end;

function TPyScripterRefactor.ResolveModuleImport(const ModuleName,
        SourceFileName : string; PrefixDotCount : integer) : TParsedModule;
var
  ModulePath : string;
  PythonPath : array of string;
  i : integer;
begin
  PythonPath := [];
  // Deal with relative imports
  if (PrefixDotCount > 0)and (SourceFileName <> '') then begin
    ModulePath := ExtractFileDir(SourceFileName);
    i := 1;
    while (ModulePath <> '') and (DirectoryExists(ModulePath)) and
      (i < PrefixDotCount) do
    begin
      Inc(i);
      ModulePath := ExtractFileDir(ModulePath);
    end;
    if (i = PrefixDotCount) and (ModulePath <> '') and
       (DirectoryExists(ModulePath))
    then
      PythonPath := [ModulePath];
  end;

  Result := GetParsedModule(ModuleName, PythonPath);
  if not Assigned(Result) and (SourceFileName <> '') then begin
    // try a relative import
    if FileIsPythonPackage(SourceFileName) then
      Result := GetParsedModule(FileNameToModuleName(SourceFileName)
        + '.' + ModuleName, []);
  end;
end;

function TPyScripterRefactor.ResolveModuleImport(ModuleImport: TModuleImport) : TParsedModule;
var
  ParentModule : TParsedModule;
  SourceFileName : string;
begin
  ParentModule := ModuleImport.GetModule;

  if Assigned(ParentModule) then
    SourceFileName := ParentModule.FileName;
  Result := ResolveModuleImport(ModuleImport.RealName,
    SourceFileName, ModuleImport.PrefixDotCount);
end;

function TPyScripterRefactor.ResolveImportedName(const Ident: string;
  ModuleImport: TModuleImport; var ErrMsg: string): TBaseCodeElement;
// May be called recursively
// fImportResolverCache is used to prevent infinite recursion
Var
  S : string;
  ImportedModule : TParsedModule;
  NameSpace : TStringList;
  Index : integer;
  ParentModule : TParsedModule;
  ModulePath : string;
  PythonPath : array of string;
  i : integer;
begin
  Result := nil;
  S := ModuleImport.Name + '.' + Ident;
  if fImportResolverCache.IndexOf(S) >= 0 then
    ErrMsg := _(SCyclicImports)
  else if (ModuleImport.RealName = '') then begin
    //  from .. import modulename
    PythonPath := [];
    if ModuleImport.PrefixDotCount > 0 then begin
      ParentModule := ModuleImport.GetModule;
      if Assigned(ParentModule) then begin
        ModulePath := ExtractFileDir(ParentModule.FileName);
        i := 1;
        while (ModulePath <> '') and (DirectoryExists(ModulePath)) and
          (i < ModuleImport.PrefixDotCount) do
        begin
          Inc(i);
          ModulePath := ExtractFileDir(ModulePath);
        end;
        if (i = ModuleImport.PrefixDotCount) and (ModulePath <> '') and
           (DirectoryExists(ModulePath)) then
        begin
          PythonPath := [ModulePath];
          Result := GetParsedModule(Ident, PythonPath);
        end;
      end;
    end;
    if not Assigned(Result) then
      ErrMsg := Format(_(SCouldNotFindModule), [Ident]);
  end else begin
    ImportedModule := ResolveModuleImport(ModuleImport);
    if not Assigned(ImportedModule) then
      ErrMsg := Format(_(SCouldNotAnalyseModule), [ModuleImport.Name])
    else begin
      fImportResolverCache.Add(S);
      NameSpace := TStringList.Create;
      NameSpace.CaseSensitive := True;
      try
        ImportedModule.GetNameSpace(NameSpace);
        Index := NameSpace.IndexOf(Ident);
        if Index >= 0 then begin
          Result := NameSpace.Objects[Index] as TBaseCodeElement;
          if Assigned(Result) and (Result is TVariable)
            and (TVariable(Result).Parent is TModuleImport)
          then
            // Resolve further
            Result := ResolveImportedName(TVariable(Result).RealName,
              TModuleImport(TVariable(Result).Parent), ErrMsg);

          if Assigned(Result) and (Result is TModuleImport) then
            Result := ResolveModuleImport(TModuleImport(Result));
        end;
        { Check whether Ident is a sub-packages }
        if not Assigned(Result) and ImportedModule.IsPackage then
          Result := GetParsedModule(ImportedModule.Name + '.' + Ident, []);

        if not Assigned(Result) then
          ErrMsg := Format(_(SCouldNotFindIdent),
          [Ident, ModuleImport.Name]);
      finally
        NameSpace.Free;
        fImportResolverCache.Delete(fImportResolverCache.IndexOf(S));
      end;
    end;
  end;
end;

function TPyScripterRefactor.GetVarType(Variable: TVariable;
  var ErrMsg: string): TCodeElement;
// Returns the type of a TVariable as a TCodeElement
// One limitation is that it does not differentiate between Classes and their
// instances, which should be OK for our needs (FindDefinition and CodeCompletion)
Var
  BaseCE, TypeCE : TBaseCodeElement;
  AVar : TVariable;
  Module : TParsedModule;
  S : string;
begin
  Result := nil;
  // Resolve imported variables
  if Variable.Parent is TModuleImport then begin
    // ResolveImportedName returns either a CodeElement or Variable whose
    // parent is not a ModuleImport
    BaseCE := ResolveImportedName(Variable.RealName,
      TModuleImport(Variable.Parent), ErrMsg);
    if not Assigned(BaseCE) then
      Exit
    else if BaseCE is TCodeElement then begin
      Result := TCodeElement(BaseCE);
      Exit;
    end else begin
      // cannot be anything but TVariable !
      Assert(BaseCE is TVariable, 'Internal Error in GetVarType');
      AVar := TVariable(BaseCE);
    end;
  end else
    AVar := Variable;

  Module := AVar.GetModule;
  S := Variable.GetDottedName;
  if fGetTypeCache.IndexOf(S) >= 0 then
    ErrMsg := _(SCyclicImports)
  else begin
    fGetTypeCache.Add(S);
    try
      // check standard types
      if vaBuiltIn in AVar.Attributes then
        Result := GetBuiltInName(AVar.ObjType)
      else if (AVar.ObjType <> '') and Assigned(AVar.Parent) and
        (AVar.Parent is TCodeElement) then
      begin
        TypeCE := FindDottedDefinition(AVar.ObjType, Module,
          TCodeElement(AVar.Parent), ErrMsg);
        if (TypeCE is TParsedClass) or
           ((TypeCE is TCodeElement) and not (vaCall in AVar.Attributes))
        then
          Result := TCodeElement(TypeCE)
        else if TypeCE is TVariable then
          Result := GetVarType(TVariable(TypeCE), ErrMsg)
        else if (TypeCE is TParsedFunction) and (vaCall in AVar.Attributes) then
          Result := GetFuncReturnType(TParsedFunction(TypeCE), ErrMsg);
      end;
      if not Assigned(Result) then
        ErrMsg := Format(_(STypeOfSIsUnknown), [AVar.Name]);
    finally
      fGetTypeCache.Delete(fGetTypeCache.IndexOf(S));
    end;
  end;
end;

function TPyScripterRefactor.FindDottedIdentInScope(const DottedIdent: string;
  Scope: TCodeElement; var ErrMsg: string): TBaseCodeElement;
// Recursive routine
// Do not call directly - It is called from FindDottedDefinition
// and assumes that the first part (Suffix) of the DottedIdent is not
// a root code element
Var
  Prefix, Suffix : string;
  NameSpace : TStringList;
  Def : TBaseCodeElement;
  Index : integer;
  VarAtts: TVariableAttributes;
begin
  Result := nil;
  Suffix := DottedIdent;
  Prefix := StrToken(Suffix, '.');
  Def := nil;

  if Scope is TParsedFunction then begin
    Scope := GetFuncReturnType(TParsedFunction(Scope), ErrMsg);
    if Scope = nil then
      Exit;
  end;

  if Prefix.IndexOfAny([')', ']', '}']) >= 0 then begin
    Prefix := GetExpressionType(Prefix, VarAtts);
    if Prefix = ''  then  begin
      ErrMsg := Format(_(SCouldNotInferType), [Prefix]);
      Exit;
    end;
  end;

  NameSpace := TStringList.Create;
  NameSpace.CaseSensitive := True;
  try
    Scope.GetNameSpace(NameSpace);
    Index := NameSpace.IndexOf(Prefix);
    if Index >= 0 then begin
      Def := NameSpace.Objects[Index] as TBaseCodeElement;

      if Assigned(Def) and (Def is TVariable) and (Def.Parent is TModuleImport) then
         Def := ResolveImportedName(TVariable(Def).RealName, TModuleImport(Def.Parent), ErrMsg);

      if Assigned(Def) and (Def is TModuleImport) then
        Def := ResolveModuleImport(TModuleImport(Def));
    end else if (Scope is TParsedModule) and TParsedModule(Scope).IsPackage then
      // check for submodules of packages
      Def := GetParsedModule(TParsedModule(Scope).Name + '.' + Prefix, []);
  finally
    NameSpace.Free;
  end;

  if Assigned(Def) then begin
    if Suffix <> '' then begin
      if Def.ClassType = TVariable then
        Def := GetVarType(TVariable(Def), ErrMsg);
      if Assigned(Def) then
        Result := FindDottedIdentInScope(Suffix, Def as TCodeElement, ErrMsg);
    end else
      Result := Def;
  end else
    ErrMsg := Format(_(SCouldNotFindIdentInScope),
          [DottedIdent, Scope.Name]);
end;

function TPyScripterRefactor.InitializeQuery : Boolean;
begin
  if not fProcessingLock.TryEnter then Exit(False);

  //ClearParsedModules;  // Do not clear.  A check is made if Source has changed
  fImportResolverCache.Clear;  // fresh start
  fGetTypeCache.Clear;  // fresh start
  fCancelled := False;
  Result := True;
end;

procedure TPyScripterRefactor.FindReferencesByCoordinates(Filename: string;
  Line, Col: integer; var ErrMsg: string; List: TStringList);
Var
  DottedIdent, LineS : string;
  ParsedModule : TParsedModule;
  Scope : TCodeElement;
  PythonPathAdder : IInterface;
  Def : TBaseCodeElement;
  Path, Server: string;
begin
  if not InitializeQuery then begin
    ErrMsg := _(SRefactoryEngineBusy);
    Exit;
  end;

  // Add the file path to the Python path - Will be automatically removed
  if not TSSHFileName.Parse(FileName, Server, Path) then
    Path := ExtractFileDir(FileName)
  else
    Path := '';
  if Length(Path) > 1 then
  begin
    PythonPathAdder :=  GI_PyControl.AddPathToInternalPythonPath(Path);
  end;

  // GetParsedModule
  ParsedModule := GetParsedModule(FileName, []);
  if not Assigned(ParsedModule) then begin
    ErrMsg := Format(_(SCouldNotLoadModule), [FileName]);
    FinalizeQuery;
    Exit;
  end;

  // Extract the identifier
  LineS := GetNthLine(ParsedModule.Source, Line);
  DottedIdent := GetWordAtPos(LineS, Col, IdentChars+['.'], True, False, True);
  DottedIdent := DottedIdent + GetWordAtPos(LineS, Col + 1, IdentChars, False, True);

  if DottedIdent = '' then begin
    ErrMsg := _(SNoIdentifier);
    FinalizeQuery;
    Exit;
 end;

  // Find scope for line
  Scope := ParsedModule.GetScopeForLine(Line);
  Def := nil;
  if not assigned(Scope) then
    ErrMsg := _(SCouldNotFindScope)
  else if (DottedIdent = Scope.Name) and (Scope.CodeBlock.StartLine = Line) then
    // Issue 967
    Def := Scope
  else
    // Find identifier in the module and scope
    Def := FindDottedDefinition(DottedIdent, ParsedModule, Scope, ErrMsg);

  if Assigned(Def) and (Def is TVariable)
    and (TVariable(Def).Parent is TModuleImport)
  then
    // Resolve further
    Def := ResolveImportedName(TVariable(Def).RealName,
      TModuleImport(TVariable(Def).Parent), ErrMsg);

  if Assigned(Def) and (Def is TModuleImport) then
    Def := ResolveModuleImport(TModuleImport(Def));

  if Assigned(Def) then
    FindReferences(Def, ErrMsg, List);

  FinalizeQuery;
end;

procedure TPyScripterRefactor.FindReferences(CE: TBaseCodeElement;
  var ErrMsg: string; List: TStringList);
Var
  Module : TParsedModule;
  SearchScope : TCodeElement;
begin
  Assert(Assigned(CE));
  Assert(Assigned(List));
  Module := CE.GetModule;
  Assert(Assigned(Module));

  if (CE is TParsedModule) or (CE.Parent is TParsedModule) then
    SearchScope := nil  // global scope
  else if CE.Parent is TParsedFunction then
    //  Local variable or argument or classes/ functions nested in functions
    SearchScope := TParsedFunction(CE.Parent)
  else if (CE.Parent is TParsedClass) and (CE.Parent.Parent is TParsedModule) then
    // methods and properties
    SearchScope := nil  // global scope
  else if CE is TParsedClass then
    // Nested functions and classes
    SearchScope := CE.Parent as TCodeElement
  else
    // e.g. methods of nested classes
    SearchScope := CE.Parent.Parent as TCodeElement;

  if Assigned(SearchScope) then
     FindReferencesInModule(CE, Module, SearchScope.CodeBlock, ErrMsg, List)
  else
    FindReferencesGlobally(CE, ErrMsg, List);
end;

procedure TPyScripterRefactor.FindReferencesGlobally(CE: TBaseCodeElement;
  var ErrMsg: string; List: TStringList);
Var
  Module, ParsedModule : TParsedModule;
  FileName, Dir : string;
  CEName, ModuleSource : string;
  i : integer;
  FindRefFileList : TStringList;
begin
  Module := CE.GetModule;
  Assert(Assigned(Module));
  FindRefFileList := TStringList.Create;

  try
    FileName := Module.FileName;
    Dir := ExtractFileDir(FileName);
    if DirIsPythonPackage(Dir) then
      Dir := GetPackageRootDir(Dir);

    // Find Python files in this directory
    GetFilesInPaths(Dir, PyIDEOptions.PythonFileExtensions, FindRefFileList, True);

    CEName := Copy(CE.Name, CharLastPos(CE.Name, WideChar('.')) + 1, MaxInt);
    for i := 0 to FindRefFileList.Count - 1 do begin
      { TODO 2 : Currently we are reading the source code twice for modules that get searched.
        Once to scan them and then when they get parsed. This can be optimised out. }
      if GetSource(FindRefFileList[i], ModuleSource) and
        (Pos(CEName, ModuleSource) > 0) then
      begin
        ParsedModule := GetParsedModule(FindRefFileList[i], []);
        if Assigned(ParsedModule) then
          FindReferencesInModule(CE, ParsedModule, ParsedModule.CodeBlock,
            ErrMsg, List);
      end;
    end;
  finally
    FindRefFileList.Free;
  end;
end;

function TPyScripterRefactor.GetBuiltInName(AName : string) : TCodeElement;
var
  ParsedBuiltInModule: TParsedModule;
begin
  ParsedBuiltInModule := GetParsedModule(GetPythonEngine.BuiltInModuleName, []);
  if not Assigned(ParsedBuiltInModule) then
    raise ERefactoringException.Create(
      'Internal Error in FindUnDottedDefinition: Could not get the Builtin module');
  (ParsedBuiltInModule as TModuleProxy).Expand;
  Result := ParsedBuiltInModule.GetChildByName(AName);
end;

function TPyScripterRefactor.GetFuncReturnType(FunctionCE: TParsedFunction;
  var ErrMsg: string): TCodeElement;
Var
  TypeCE : TBaseCodeElement;
  S : string;
begin
  Result := nil;

  // special case for built-in open
  if FunctionCE.Name = 'open' then begin
    Result := GetBuiltInName('file');
    if (Result = nil) then begin
      Result := GetParsedModule('_io', []);
      if Assigned(Result) then begin
        if Result is TModuleProxy then
          TModuleProxy(Result).Expand;
        Result := Result.GetChildByName('TextIOWrapper');
      end;
    end;
    Exit;
  end;

  // Exit if no return type is given
  // Functions from Module proxies will have Return type = ''
  if FunctionCE.ReturnType = '' then begin
    ErrMsg := Format(_(SCouldInferFunctionReturnType), [FunctionCE.Name]);
    Exit;
  end;

  S := FunctionCE.GetDottedName;
  if fGetTypeCache.IndexOf(S) >= 0 then
    ErrMsg := _(SCyclicTypeDependency)
  else begin
    fGetTypeCache.Add(S);
    try
      if vaBuiltIn in FunctionCE.ReturnAttributes then
        Result := GetBuiltInName(FunctionCE.ReturnType)
      else begin
        TypeCE := FindDottedDefinition(FunctionCE.ReturnType,
          FunctionCE.GetModule, FunctionCE, ErrMsg);

        if (TypeCE is TParsedClass) or
           ((TypeCE is TCodeElement) and not (vaCall in FunctionCE.ReturnAttributes))
        then
          Result := TCodeElement(TypeCE)
        else if TypeCE is TVariable then
          Result := GetVarType(TVariable(TypeCE), ErrMsg)
        else if (TypeCE is TParsedFunction) and
          (vaCall in FunctionCE.ReturnAttributes)
        then
          Result := GetFuncReturnType(TParsedFunction(TypeCE), ErrMsg);
      end;
    finally
      fGetTypeCache.Delete(fGetTypeCache.IndexOf(S));
    end;
  end;
end;

procedure TPyScripterRefactor.FindReferencesInModule(CE: TBaseCodeElement;
  Module: TParsedModule; CodeBlock: TCodeBlock; var ErrMsg: string;
  List: TStringList);
Var
  SL : TStringList;
  Line, CEName, CEModuleName : string;
  i, j : integer;
  LinePos: Integer;
  Found : Boolean;
  EndPos : integer;
  Def : TBaseCodeElement;
  Start: Integer;
  TestChar: WideChar;
  ModuleIsImported : boolean;
begin
  // the following if for seaching for sub-modules and sub-packages
  CEName := Copy(CE.Name, CharLastPos(CE.Name, WideChar('.')) + 1, MaxInt);
  ModuleIsImported := False;
  if not AnsiSameText(CE.GetModule.FileName, Module.FileName) then begin
    // Check (approximately!) whether CE.GetModule gets imported in Module
    CEModuleName := CE.GetModule.Name;
    if CharPos(CE.GetModule.Name, WideChar('.')) > 0 then
      CEModuleName := Copy(CEModuleName, CharLastPos(CEModuleName, WideChar('.')) + 1, MaxInt);
    for i := 0 to Module.ImportedModules.Count - 1 do begin
      if Pos(CEModuleName, TModuleImport(Module.ImportedModules[i]).Name) >0 then begin
        ModuleIsImported := True;
        break;
      end;

      // the following is for dealing with the syntax
      //      from package import submodule
      // if CE.Module is a submodule and subpackage
      if CharPos(CE.GetModule.Name, WideChar('.')) > 0 then begin
        if Assigned(TModuleImport(Module.ImportedModules[i]).ImportedNames) then
          for j := 0 to TModuleImport(Module.ImportedModules[i]).ImportedNames.Count - 1 do
            if Pos(CEModuleName, TVariable(
              TModuleImport(Module.ImportedModules[i]).ImportedNames[j]).Name) >0 then
            begin
              ModuleIsImported := True;
              break;
            end;
      end;
    end;
  end else
    ModuleIsImported := True;

  if not ModuleIsImported then Exit; // no need to process further

  // if Module is TModuleProxy then MaskedSource will be '' and Codeblock.StartLine will be 0
  // so no searching will take place.

  SL := TStringList.Create;
  SL.Text := Module.MaskedSource;
  try
    for i := Max(1 ,CodeBlock.StartLine)-1 to Min(SL.Count, CodeBlock.EndLine) - 1 do begin
      Line := SL[i];
      EndPos := 0;
      Repeat
        LinePos := PosEx(CEName, Line, EndPos + 1);
        Found := LinePos > 0;
        if Found then begin
          // check if it is a whole word
          EndPos := LinePos + Length(CEName) - 1;

          Start := LinePos - 1; // Point to previous character
          if (Start > 0) then
          begin
            TestChar := Line[Start];
            if IsCharAlphaNumericW(TestChar) or (TestChar = WideChar('_')) then
              Continue;
          end;
          if EndPos < Length(Line) then begin
            TestChar := Line[EndPos+1];  // Next Character
            if IsCharAlphaNumericW(TestChar) or (TestChar = WideChar('_')) then
              Continue;
          end;
          // Got Match - now process it  -------------------
          Def := FindDefinitionByCoordinates(Module.FileName, i+1, LinePos, ErrMsg, False);
          if Assigned(Def) and (Def is TVariable)
            and (TVariable(Def).Parent is TModuleImport)
          then
            // Resolve further
            Def := ResolveImportedName(TVariable(Def).RealName,
              TModuleImport(TVariable(Def).Parent), ErrMsg);

          if Assigned(Def) and (Def is TModuleImport) then
            Def := ResolveModuleImport(TModuleImport(Def));

          if Def = CE then begin
            //  add two lines: one with position and the other with the line
            List.Add(Format(FilePosInfoFormat, [Module.FileName, i+1, LinePos]));
            List.Add(Line);
          end;
          // End of processing  -------------------
        end;
      Until not Found;
    end;
  finally
    SL.Free;
  end;
end;


initialization
  PyScripterRefactor := TPyScripterRefactor.Create;
finalization
  PyScripterRefactor.Free;
end.
