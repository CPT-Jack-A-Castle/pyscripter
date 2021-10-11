{-----------------------------------------------------------------------------
 Unit Name: cTools
 Author:    Kiriakos Vlahos
 Date:      02-Jun-2005
 Purpose:   Class definitions for Command Line Tools
 History:
-----------------------------------------------------------------------------}

unit cTools;

interface
uses
  System.SysUtils,
  System.Classes,
  Vcl.ActnList;

type
  TProcessStdInputOption = (piNone, piWordAtCursor, piCurrentLine, piSelection,
                                                    piActiveFile);
  TProcessStdOutputOption = (poNone, poWordAtCursor, poCurrentLine, poSelection,
                                                     poActiveFile, poNewFile);
  TToolContext = (tcAlwaysEnabled, tcActiveFile, tcActivePythonFile, tcSelectionAvailable);

  TSaveFiles = (sfNone, sfActive, sfAll);

  TExternalTool = class;

  TExternalToolExecute = procedure(Tool: TExternalTool) of object;

  {
     Describes the properties of a command line tool
  }
  TExternalTool = class(TPersistent)
  private
    fApplicationName: string;
    fParameters: string;
    fProcessInput: TProcessStdInputOption;
    fProcessOutput: TProcessStdOutputOption;
    fCaptureOutput: Boolean;
    fTimeOut: Integer;
    fWaitForTerminate: Boolean;
    fConsoleHidden: Boolean;
    fWorkingDirectory: string;
    fDescription: string;
    fCaption: string;
    fShortCut: TShortCut;
    fParseMessages : boolean;
    fParseTraceback : boolean;
    fMessagesFormat : string;
    fContext: TToolContext;
    fSaveFiles : TSaveFiles;
    fEnvironment : TStrings;
    fUseCustomEnvironment : Boolean;
    FUseUtf8: Boolean;
    procedure SetEnvironment(const Value: TStrings);
    function IsMessageFormatStore: Boolean;
  public
    class var ExternalToolExecute: TExternalToolExecute;
    constructor Create;
    destructor Destroy; override;
    procedure Execute;
    procedure Assign(Source: TPersistent); override;
  published
    // The caption of the Menu Item corresponding to this tool
    property Caption : string read fCaption write fCaption;
    // The hint of the Menu Item corresponding to this tool
    property Description : string read fDescription write fDescription;
    property ApplicationName: string read fApplicationName write fApplicationName;
    property Parameters: string read fParameters write fParameters;
    property WorkingDirectory : string read fWorkingDirectory write fWorkingDirectory;
    property ShortCut : TShortCut read fShortCut write fShortCut default 0;
    // External Tool action context (tcAlwaysEnabled, tcActiveFile, tcSelectionAvailable)
    property Context : TToolContext read fContext write fContext
      default tcAlwaysEnabled;
    // Save file option (sfNone, sfActive, sfAll)
    property SaveFiles : TSaveFiles read fSaveFiles write fSaveFiles default sfNone;
    // Standard Input option
    //  piNone:  No standard input
    //  piWordAtCursor: Word at cursor
    //  piCurrentLine: Current line
    //  piSelection: Selection
    //  piActiveFile: active file
    property ProcessInput : TProcessStdInputOption read fProcessInput
      write fProcessInput default piNone;
    // Standard output option
    //  poNone:  Do nothing
    //  poWordAtCursor: Replace word at cursor
    //  poCurrentLine: Replace current line
    //  poSelection: Replace selection
    //  poActiveFile: Replace active file
    //  poNewFile: Place in new file
    property ProcessOutput : TProcessStdOutputOption read fProcessOutput
      write fProcessOutput default poNone;
    // Parse File Line LinePos info from output and put it in the Messages Window
    property ParseMessages : boolean read fParseMessages write fParseMessages
      default False;
    // Parse TraceBack and Syntax Errors from Python output and put it in the Messages Window
    property ParseTraceback : boolean read fParseTraceback write fParseTraceback
      default False;
    // Grep Expression for the parsing output lines for file/Line/Pos information
    // Can use the parameters $[Filename], $[LineNumber], $[Line], $[Column]
    property MessagesFormat : string read fMessagesFormat write fMessagesFormat
      stored IsMessageFormatStore;
    // Capture command line output and place it in the Output Window
    property CaptureOutput : Boolean read fCaptureOutput write fCaptureOutput
      default True;
    // Hide Console or External Tool window
    property ConsoleHidden : Boolean read fConsoleHidden write fConsoleHidden
      default True;
    // Non-blocking wait for termination of the External tool
    // Required for ParseMessage, ParseTraceback and other options
    property WaitForTerminate: Boolean read fWaitForTerminate write
      fWaitForTerminate default True;
    // Give the user the oportunity to terminate the External tool after Timeout ms
    // A value of zero disables this feature
    property TimeOut : Integer read fTimeOut write fTimeOut default 0;
    // Use the Custom Enviroment specified by the Environment property
    property UseCustomEnvironment : boolean read fUseCustomEnvironment
      write fUseCustomEnvironment default False;
    // Custom Enviroment
    property Environment : TStrings read fEnvironment write SetEnvironment
      stored fUseCustomEnvironment;
    property UseUtf8: Boolean read FUseUtf8 write FUseUtf8 default False;
  end;

  // Differs only in persistence
  TExternalRun = class(TExternalTool)
  published
    property SaveFiles default sfAll;
    property Context default tcActiveFile;
    property ParseTraceback default True;
  end;

  TToolItem = class(TCollectionItem)
  private
    fExternalTool : TExternalTool;
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property ExternalTool : TExternalTool read fExternalTool
      write fExternalTool;
  end;

  TExternalToolAction = class(TAction)
  private
    fExternalTool : TExternalTool;
  protected
    procedure Change; override;
  public
    function Execute: Boolean; override;
    function Update: Boolean; override;
    constructor CreateExtToolAction(AOwner: TComponent; ExternalTool : TExternalTool);
  end;

{ Expands environment variables }
function ExpandEnv(const S: string): string;
{ Surrounds string with quotes when it contains spaces and is not quoted }
function AddQuotesUnless(const S: string): string;
{ Prepares an application name or the command line parameters for execution }
function PrepareCommandLine(S: string): string;

Const
  GrepFileNameParam = '$[FileName]';
  GrepLineNumberParam = '$[LineNumber]';
  GrepColumnNumberParam = '$[ColumnNumber]';

Var
  { A persisted collection of user-defined tools }
  ToolsCollection : TCollection;
  { External Python Tool }
  ExternalPython : TExternalTool;

implementation

uses
  Winapi.Windows,
  Vcl.Menus,
  JclStrings,
  JvGnuGetText,
  cParameters,
  uEditAppIntfs,
  uCommonFunctions,
  cPyScripterSettings;


function ExpandEnv(const S: string): string;
var
  r: array[0..MAX_PATH] of WideChar;
begin
  ExpandEnvironmentStringsW(PWideChar(S), @r, MAX_PATH);
  Result := r;
end;

function AddQuotesUnless(const S: string): string;
begin
  Result := Trim(S);
  if (Pos(' ', Result) <> 0) and
     ((Result[1] <> '"') or (Result[Length(Result)] <> '"')) then
    Result := '"' + Result + '"';
end;

function PrepareCommandLine(S: string): string;
begin
  S := ExpandEnv(S);
  S:= Parameters.ReplaceInText(S);
  Result := Trim(S);
end;

{ TTool }

procedure TToolItem.Assign(Source: TPersistent);
begin
  if Source is TToolItem then with TToolItem(Source) do begin
    Self.fExternalTool.Assign(ExternalTool);
  end else
    inherited;
end;

constructor TToolItem.Create(Collection: TCollection);
begin
  inherited;
  fExternalTool := TExternalTool.Create;
end;

destructor TToolItem.Destroy;
begin
  fExternalTool.Free;
  inherited;
end;

function TToolItem.GetDisplayName: string;
begin
  Result := StrRemoveChars(_(fExternalTool.Caption), ['&']);
end;

{ TExternalTool }

procedure TExternalTool.Assign(Source: TPersistent);
begin
  if Source is TExternalTool then with TExternalTool(Source) do begin
    Self.fCaption := Caption;
    Self.fDescription := Description;
    Self.fShortCut := ShortCut;
    Self.fContext := Context;
    Self.fSaveFiles := SaveFiles;
    Self.fApplicationName := ApplicationName;
    Self.fParameters := Parameters;
    Self.fWorkingDirectory := WorkingDirectory;
    Self.fProcessInput := ProcessInput;
    Self.fProcessOutput := ProcessOutput;
    Self.fParseMessages := ParseMessages;
    Self.fParseTraceback := ParseTraceback;
    Self.fMessagesFormat := MessagesFormat;
    Self.fCaptureOutput := CaptureOutput;
    Self.fConsoleHidden := ConsoleHidden;
    Self.fTimeOut := TimeOut;
    Self.fWaitForTerminate := WaitForTerminate;
    Self.fUseCustomEnvironment := UseCustomEnvironment;
    Self.fEnvironment.Assign(Environment);
  end else
    inherited;
end;

constructor TExternalTool.Create;
begin
  inherited;
  fProcessInput := piNone;
  fProcessOutput := poNone;
  fCaptureOutput := True;
  fConsoleHidden := True;
  fTimeOut := 0;
  fWaitForTerminate := True;
  fParseMessages := False;
  fContext := tcAlwaysEnabled;
  fSaveFiles := sfNone;
  fMessagesFormat := GrepFileNameParam + ' ' + GrepLineNumberParam;
  fEnvironment := TStringList.Create;
end;

destructor TExternalTool.Destroy;
begin
  fEnvironment.Free;
  inherited;
end;

procedure TExternalTool.Execute;
begin
  if Assigned(ExternalToolExecute) then
    ExternalToolExecute(Self);
end;

function TExternalTool.IsMessageFormatStore: Boolean;
begin
  Result := fParseMessages and (fMessagesFormat <> (GrepFileNameParam + ' ' + GrepLineNumberParam));
end;

procedure TExternalTool.SetEnvironment(const Value: TStrings);
begin
  fEnvironment.Assign(Value);
end;

{ TExternalToolAction }

procedure TExternalToolAction.Change;
begin
  inherited;
  if Assigned(fExternalTool) then
    fExternalTool.ShortCut := ShortCut;
end;

constructor TExternalToolAction.CreateExtToolAction(AOwner: TComponent;
  ExternalTool: TExternalTool);
var
  S: string;
  AppFile: string;
begin
  inherited Create(AOwner);
  fExternalTool := ExternalTool;
  if Assigned(fExternalTool) then begin
    ShortCut := fExternalTool.ShortCut;
    Caption := _(fExternalTool.Caption);
    S := StrRemoveChars(Caption , [' ', '&', '.']);  // Fix error reported by David Funtowiez
    if IsValidIdent(S) then
      Name := 'actTools' + S;
    Category := 'External Tools';
    Hint := _(fExternalTool.Description);
    ImageIndex := -1;
    if (fExternalTool.ApplicationName <> '') then begin
      AppFile := PrepareCommandLine(fExternalTool.ApplicationName);
      if FileExists(AppFile) then
        ImageIndex := GetIconIndexFromFile(AppFile, True);
    end;
  end;
end;

function TExternalToolAction.Execute: Boolean;
begin
  if Assigned(fExternalTool) and Assigned(fExternalTool.ExternalToolExecute) then begin
    TThread.ForceQueue(nil, procedure
    begin
      fExternalTool.Execute;
    end);
  end;
  Result := True;
end;

function TExternalToolAction.Update: Boolean;
begin
  Result := True;
  if Assigned(fExternalTool) then begin
    case fExternalTool.Context of
      tcAlwaysEnabled : Enabled := True;
      tcActiveFile : Enabled := Assigned(GI_ActiveEditor);
      tcActivePythonFile :
        Enabled := Assigned(GI_ActiveEditor) and GI_ActiveEditor.HasPythonFile;
      tcSelectionAvailable : Enabled :=
        Assigned(GI_ActiveEditor) and GI_ActiveEditor.SynEdit.SelAvail;
    end;
  end else
    Enabled := False;
end;

initialization
  ToolsCollection := TCollection.Create(TToolItem);
  // Add a few standard tools to the collection
  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Python &Interpreter');
    Description := _('External Python Interpreter');
    ApplicationName := '$[PythonExe-Short]';
    WorkingDirectory := '$[ActiveDoc-Dir]';
    SaveFiles := sfAll;
    ParseMessages := False;
    CaptureOutput := False;
    ConsoleHidden := False;
    WaitForTerminate := False;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Install Packages with pip');
    Description := _('Install Python packages');
    ApplicationName := '$[PythonDir-Short]Scripts\pip.exe';
    Parameters := 'install -U $[Package?Package Name]';
    ParseMessages := False;
    CaptureOutput := True;
    ConsoleHidden := True;
    WaitForTerminate := True;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Python&Win help');
    Description := _('Show PythonWin Help');
    ApplicationName := '$[PythonExe-Path-Short]Lib\site-packages\PyWin32.chm';
    ParseMessages := False;
    CaptureOutput := False;
    ConsoleHidden := False;
    WaitForTerminate := False;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Check &Indentation');
    Description := _('Check the indentation of the Python program');
    ApplicationName := '$[PythonExe-Short]';
    Parameters := '-m tabnanny "$[ActiveDoc]"';
    WorkingDirectory := '$[ActiveDoc-Dir]';
    ShortCut := Vcl.Menus.Shortcut(Ord('T'), [ssShift, ssCtrl]);
    Context := tcActivePythonFile;
    SaveFiles := sfActive;
    ParseTraceback := True;
    ParseMessages := True;
    CaptureOutput := True;
    ConsoleHidden := True;
    WaitForTerminate := True;
    MessagesFormat := GrepFileNameParam + ' '+GrepLineNumberParam;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Command Prompt');
    Description := _('Start a console at the directory of the active file');
    ApplicationName := '%COMSPEC%';
    WorkingDirectory := '$[ActiveDoc-Dir]';
    SaveFiles := sfAll;
    ParseMessages := False;
    CaptureOutput := False;
    ConsoleHidden := False;
    WaitForTerminate := False;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Profile');
    Description := _('Profile active file');
    ApplicationName := '$[PythonExe-Short]';
    Parameters := '-m profile "$[ActiveDoc]" $[CmdLineArgs]';
    WorkingDirectory := '$[ActiveDoc-Dir]';
    Context := tcActivePythonFile;
    SaveFiles := sfActive;
    ParseTraceback := True;
    CaptureOutput := True;
    ConsoleHidden := True;
    WaitForTerminate := True;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := 'Py&lint';
    Description := _('PyLint tool (www.pylint.org)');
    ApplicationName :=  '$[PythonDir-Short]Scripts\pylint.exe';
    Parameters := '-f parseable "$[ActiveDoc]"';
    ShortCut := Vcl.Menus.Shortcut(Ord('L'), [ssShift, ssCtrl]);
    Context := tcActivePythonFile;
    SaveFiles := sfAll;
    ParseTraceback := True;
    ParseMessages := True;
    CaptureOutput := True;
    ConsoleHidden := True;
    WaitForTerminate := True;
    MessagesFormat := Format('%s:%s: ', [GrepFileNameParam, GrepLineNumberParam]);
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Advanced Replace');
    Description := _('Advanced Search and replace');
    ApplicationName := '$[PythonExe-Short]';
    Parameters := '-c "import sys, re;l=sys.stdin.read();sys.stdout.write(re.sub(''$[st?Search Text:]'', ''$[rt?Replace Text:]'', l))"';
    Context := tcSelectionAvailable;
    SaveFiles := sfNone;
    ProcessInput := piSelection;
    ProcessOutput := poSelection;
    ParseMessages := False;
    CaptureOutput := False;
    ConsoleHidden := True;
    WaitForTerminate := True;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('Sort Selection');
    Description := _('Sort the selected editor block ("one-liner" demo)');
    ApplicationName := '$[PythonExe-Short]';
    Parameters := '-c "import sys;l=sys.stdin.readlines();l.sort();sys.stdout.writelines(l)"';
    ShortCut := Vcl.Menus.Shortcut(Ord('S'), [ssShift, ssCtrl]);
    Context := tcSelectionAvailable;
    SaveFiles := sfNone;
    ProcessInput := piSelection;
    ProcessOutput := poSelection;
    ParseMessages := False;
    CaptureOutput := False;
    ConsoleHidden := True;
    WaitForTerminate := True;
  end;

  with (ToolsCollection.Add as TToolItem).ExternalTool do begin
    Caption := _('&Re-indent');
    Description := _('Re-indent the active file');
    ApplicationName := '$[PythonExe-Short]';
    Parameters := '$[PythonDir-Short]Tools\Scripts\reindent.py';
    Context := tcActivePythonFile;
    SaveFiles := sfNone;
    ProcessInput := piActiveFile;
    ProcessOutput := poActiveFile;
    ParseMessages := False;
    CaptureOutput := True;
    ConsoleHidden := True;
    WaitForTerminate := True;
  end;

  // Create a Python External Run tool which is used in the run menu
  ExternalPython := TExternalRun.Create;
  with ExternalPython do begin
    Caption := _('Python Interpreter');
    Description := _('External Python Interpreter');
    ApplicationName := '$[PythonExe-Short]';
    Parameters := '$[ActiveDoc-Short] $[CmdLineArgs]';
    WorkingDirectory := '$[ActiveDoc-Dir]';
    SaveFiles := sfAll;
    Context := tcActiveFile;
    ParseTraceback := True;
    CaptureOutput := True;
    ConsoleHidden := True;
    WaitForTerminate := True;
  end;

finalization
  ToolsCollection.Free;
  ExternalPython.Free;
end.
