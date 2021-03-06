﻿{**************************************************************************************************}
{                                                                                                  }
{ Plastic SCM for Delphi plugin (Plastic4Delphi)                                                   }
{                                                                                                  }
{ The contents of this file are subject to the Mozilla Public License Version 1.1 (the "License"); }
{ you may not use this file except in compliance with the License. You may obtain a copy of the    }
{ License at http://www.mozilla.org/MPL/                                                           }
{                                                                                                  }
{ Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF   }
{ ANY KIND, either express or implied. See the License for the specific language governing rights  }
{ and limitations under the License.                                                               }
{                                                                                                  }
{ The Initial Developer of the Original Code is Chris Fairall,                                     }
{ but most code is completely rewritten.                                                           }
{                                                                                                  }
{ Contributor(s): André Mussche (andre.mussche at gmail dot com)                                   }
{                 Consultant of: DTS b.v, www.dts.nl                                               }
{ Hired by      : RBK Group, www.rbk.nl                                                            }
{                 Wik Groeneveld (wgroeneveld at rbk dot nl)                                       }
{                                                                                                  }
{ All rights reserved.                                                                             }
{**************************************************************************************************}
unit PlasticExpert;

interface

uses
  DbugIntf,
  Generics.Collections,
  Windows, SysUtils, Graphics, Classes, Menus, ActnList, ToolsAPI, Dialogs, Forms,
  PlasticEngine, PlasticUtils,
  ComCtrls, contnrs, SyncObjs;

  { TODO -oAM : Make "offline" option (in case of no network etc) }
  { TODO -oAM : Add file history option, use client.conf + DiffTools for WinMerge etc}
  { TODO -oAM : Add file annotate/blame option }
  { TODO -oAM : Add file rename option: needs new Plastic Client which support "only rename on server" }

const
  C_Plastic_SCM = 'Plastic SCM';

type
  TPlasticExpert = class(TObject)
  private
    FMenuPlastic: TMenuItem;
    FActionStatus, FActionReset,
    FActionShelve, FActionDelete, FActionRename, FActionConsole,
    FActionAdd,
    FActionCheckout,
    FActionWriteable,
    FActionCheckin,
    FActionUncheckout,
    FActionUpdate,
    FActionDiff,
    FActionAddAll,
    FActionPlasticClient: TAction;
    FActionList: TObjectDictionary<TAction,integer>;
    FFileInfo        : TStringList;
    FFileName        : String;
    FLastChecked     : TDateTime;
    function  GetSourceEditor : IOTASourceEditor;
  protected
    FCurrentFile: string;
    FLastUpdate,
    FBusyWithUpdate: TDatetime;

    procedure ListFiles(aFileList : TStrings);
    function  GetFileInfo(psFileName : String; out pslInfo : TPlasticFileInfo; pbForce : Boolean = false) : Boolean;
    function  GetModuleFileInfo(const aFile: string; out pslInfo : TPlasticFileInfo; pbForce : Boolean = false) : Boolean;
    function  GetModuleFile: string;

    procedure ReloadFiles;
    function  Modified : Boolean;
    procedure ForceSaveModule;
    procedure RemoveReadonlyEditorFlag;

    procedure CreateMenu;
    function  AddAction(psCaption, psHint, psName, psImageRes, psImageName : String;
                       ExecuteEvent, UpdateEvent : TNotifyEvent) : TAction;
    function  AddMenu(pAction : TAction) : TMenuItem;
    procedure RemoveActionFromToolbar(AAction : TAction);
    procedure RemoveAction(aAction: TAction; aToolbar: TToolbar);
    procedure UpdateActionImages;

    procedure HandleException(E:Exception);overload;
    procedure HandleException(Sender: TObject);overload;

    procedure GeneralUpdate(Sender : TObject);
    procedure MenuExecute(Sender : TObject);
    procedure StatusExecute(Sender : TObject);
    procedure ShelveExecute(Sender : TObject);
    procedure RenameExecute(Sender : TObject);
    procedure DeleteExecute(Sender : TObject);
    procedure ConsoleExecute(Sender : TObject);
    procedure CheckoutExecute(Sender : TObject);
    procedure LocalWriteableExecute(Sender : TObject);
    procedure AddExecute(Sender : TObject);
    procedure CheckinExecute(Sender : TObject);
    procedure UncheckoutExecute(Sender : TObject);
    procedure DiffExecute(Sender : TObject);
    procedure UpdateExecute(Sender : TObject);
    procedure AddAllExecute(Sender : TObject);
    procedure PlasticClientExecute(Sender : TObject);
  public
    constructor Create; virtual;
    destructor  Destroy; override;

    procedure UpdateMenu(aForced: boolean);
  end;

var
  GPlasticExpert : TPlasticExpert;

implementation

uses
  Controls,
  PlasticNotify, DateUtils, PlasticAsync, Messages, fDebugConsole;

{ TPlasticExpert }

constructor TPlasticExpert.Create;
begin
  {$IFDEF DEBUG}
  SendDebug(dlObject, 'Creating Plastic SCM Expert 1.0.2 (debug version)');
  {$ELSE}
    {$IFDEF RELEASE}
    SendDebug(dlObject, 'Creating Plastic SCM Expert 1.0.2 (release)');
    {$ELSE}
    SendDebug(dlObject, 'Creating Plastic SCM Expert 1.0.2 (?)');
    {$ENDIF}
  {$ENDIF}
  inherited Create;

  FFileInfo := TStringList.Create;
  FFileName := '';
  FLastChecked := 0;

  FActionList := TObjectDictionary<TAction,Integer>.Create([doOwnsKeys]);
  CreateMenu;
end;

procedure TPlasticExpert.CreateMenu;
var
  Service : INTAServices;
  iPos    : Integer;
  miAfter : TMenuItem;
begin
  SendDebug(dlObject, 'TPlasticExpert: inserting menu items into Delphi IDE');
  Service := (BorlandIDEServices as INTAServices);

  { Main menu item }
  FMenuPlastic             := TMenuItem.Create(Service.MainMenu);
  FMenuPlastic.Caption     := C_Plastic_SCM;
  FMenuPlastic.AutoHotkeys := maAutomatic;

  FMenuPlastic.Action := AddAction(C_Plastic_SCM, C_Plastic_SCM,
                           'PlasticSCM', '', '',
                           MenuExecute, GeneralUpdate);

  miAfter := Service.MainMenu.Items.Find('&Window');
  if miAfter = nil then
    iPos := 9
  else
    iPos := miAfter.MenuIndex;
  Service.MainMenu.Items.Insert(iPos, FMenuPlastic);

  FActionStatus := AddAction('<Status>', 'Status of current file',
                           'PlasticStatus', '', '',
                           StatusExecute, GeneralUpdate);
  AddMenu(FActionStatus);

  FActionReset  := AddAction('Refresh status', 'Refresh status of current file',
                           'PlasticReset', '', '',
                           StatusExecute, GeneralUpdate);
  AddMenu(FActionReset);
  FActionReset.Visible := False; //not needed anymore?

  FMenuPlastic.NewBottomLine;
  //----------------------------------------------------------------------------

  FActionWriteable := AddAction('&Make local writeable', 'Make local writeable|.', 'LocalWriteable',
                            '', 'LocalWriteable', LocalWriteableExecute, nil);
  AddMenu(FActionWriteable);

  FActionCheckout := AddAction('&Check out...', 'Open for Edit|.', 'PlasticCheckOut',
                            'plasticcheckout16', 'PlasticCheckOut', CheckoutExecute, nil);
  AddMenu(FActionCheckout);

  FActionUncheckout := AddAction('&Undo checkout...', 'Undo checkout|', 'PlasticUncheckout',
                             'undo16', 'PlasticUncheckout', UncheckoutExecute, nil);
  AddMenu(FActionUncheckout);

  FActionCheckin := AddAction('&Check in...', 'Check in|', 'PlasticCheckin',
                             'plasticcheckin16', 'PlasticCheckin', CheckinExecute, nil);
  AddMenu(FActionCheckin);

  FMenuPlastic.NewBottomLine;
  //----------------------------------------------------------------------------

  FActionShelve := AddAction('Shelve file', 'Shelve (store) to Plastic DB',
                             'PlasticShelve', '', '',
                             ShelveExecute, nil);
  AddMenu(FActionShelve);

  FActionUpdate := AddAction('Update (forced)...', 'Update|', 'PlasticUpdate',
                           'plasticupdate16', 'PlasticUpdate', UpdateExecute, nil);
  AddMenu(FActionUpdate);

  FActionDiff := AddAction('&Diff with previous...', 'Diff with previous|',
                           'PlasticDiff', 'plasticdiff16', 'PlasticDiff',
                           DiffExecute, nil);
  AddMenu(FActionDiff);

  FMenuPlastic.NewBottomLine;
  //----------------------------------------------------------------------------

  FActionRename := AddAction('Rename file', 'Rename file(s)',
                           'PlasticRename', '', '',
                           RenameExecute, nil);
  AddMenu(FActionRename);

  FActionDelete := AddAction('Delete file', 'Delete files(s)',
                           'PlasticDelete', 'plasticremove16', 'PlasticDelete',
                           DeleteExecute, nil);
  AddMenu(FActionDelete);

  FActionAdd := AddAction('&Add file...', 'Add To Plastic|',
                           'PlasticAdd', 'plasticadd16', 'PlasticAdd',
                           AddExecute, nil);
  AddMenu(FActionAdd);

  FActionAddAll := AddAction('Add All Files In Project...', 'Add All|',
                             'PlasticAddAll', '', '', AddAllExecute, nil);
  AddMenu(FActionAddAll);
  FMenuPlastic.NewBottomLine;
  //----------------------------------------------------------------------------

  FActionPlasticClient := AddAction(
                               Format('Plastic SCM client (version: %s)',[TPlasticEngine.GetPlasticVersion]),
                               'Plastic SCM Client|', 'PlasticClient',
                               'Plastic16_32b', 'PlasticClient', PlasticClientExecute, nil);
  AddMenu(FActionPlasticClient);

  DebugConsole; //dummy call to create form
  FActionConsole := AddAction('Debug Console', 'Debug Console|', 'DebugConsole',
                               '', '', ConsoleExecute, nil);
  AddMenu(FActionConsole);

  UpdateActionImages;
end;

destructor TPlasticExpert.Destroy;
var
  Service : INTAServices;
  action: TAction;
begin
  try
    Service := (BorlandIDEServices as INTAServices);

    { Destroy the menu items }
    { Sub-menu items are freed by their owner - FMenuPlastic when it is freed... }
    Service.MainMenu.Items.Remove(FMenuPlastic);
    FMenuPlastic.Free;

    { Remove actions from any toolbars the user may have added them to. }
    {
    RemoveActionFromToolbar(FActionStatus);
    RemoveActionFromToolbar(FActionShelve);
    RemoveActionFromToolbar(FActionDelete);
    RemoveActionFromToolbar(FActionRename);
    RemoveActionFromToolbar(FActionConsole);
    RemoveActionFromToolbar(FActionAdd);
    RemoveActionFromToolbar(FActionCheckout);
    RemoveActionFromToolbar(FActionCheckin);
    RemoveActionFromToolbar(FActionUncheckout);
    RemoveActionFromToolbar(FActionUpdate);
    RemoveActionFromToolbar(FActionDiff);
    RemoveActionFromToolbar(FActionAddAll);
    RemoveActionFromToolbar(FActionPlasticClient);
    }
    for action in FActionList.Keys do
      RemoveActionFromToolbar(action);
    FActionList.Free;

    FFileInfo.Free;

    DebugConsole.Free;

    inherited Destroy;
  except
    on E:Exception do HandleException(E);
  end;
end;

procedure TPlasticExpert.CheckoutExecute(Sender: TObject);
var
  slFiles  : TStrings;
begin
  SendDebugFmtEx_Start(dlObject, '-> CheckoutExecute', [], mtInformation);
  slFiles := TStringList.Create;
  try
    FActionStatus.Caption := 'Status: check out pending...';

    ListFiles(slFiles);
    try
      PlasticIDENotifier.PendingCheckoutOfFiles(slFiles);

      //save editor changes first, otherwise changes are lost!
      if Modified then ForceSaveModule;

      if not TPlasticEngine.CheckoutFiles(slFiles) then
        MessageDlg('Checkout failed!'#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);
    finally
      PlasticIDENotifier.PendingCheckoutOfFiles(nil);
    end;

    ReloadFiles;
  finally
    slFiles.Free;
    SendDebugFmtEx_End(dlObject, '<- CheckoutExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.CheckinExecute(Sender: TObject);
var
  slFiles  : TStrings;
begin
  SendDebugFmtEx_Start(dlObject, '-> CheckinExecute', [], mtInformation);
  try
    slFiles := TStringList.Create;
    try
      FActionStatus.Caption := 'Status: check in pending...';

      //save editor changes first
      if Modified then ForceSaveModule;

      ListFiles(slFiles);
      if not TPlasticEngine.CheckinFiles(slFiles) then
        MessageDlg('Checkin failed!'#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);
    finally
      slFiles.Free;
    end;

    ReloadFiles;
  finally
    SendDebugFmtEx_End(dlObject, '<- CheckinExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.UncheckoutExecute(Sender: TObject);
var
  slFiles  : TStrings;
begin
  SendDebugFmtEx_Start(dlObject, '-> UncheckoutExecute', [], mtInformation);
  try
    if MessageDlg('Are you sure you want to uncheckout this file?', Dialogs.mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      FActionStatus.Caption := 'Status: uncheckout pending...';

      slFiles := TStringList.Create;
      try
        ListFiles(slFiles);
        if not TPlasticEngine.UndoCheckoutFiles(slFiles) then
          MessageDlg('Undo checkout failed!'#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);
      finally
        slFiles.Free;
      end;

      ReloadFiles;
    end;
  finally
    SendDebugFmtEx_End(dlObject, '<- UncheckoutExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.AddExecute(Sender: TObject);
var
  Files: TStrings;
  Serv : IOTAModuleServices;
begin
  SendDebugFmtEx_Start(dlObject, '-> AddExecute', [], mtInformation);
  Files := TStringList.Create;
  try
    //try save first if new?
    Serv := (BorlandIDEServices as IOTAModuleServices);
    if Serv.CurrentModule <> nil then
    if not FileExists(Serv.CurrentModule.FileName) then
      Serv.CurrentModule.Save(False, True);
    //save editor changes first
    if Modified then ForceSaveModule;

    FActionStatus.Caption := 'Status: add pending...';

    //add
    ListFiles(Files);
    if not TPlasticEngine.AddFiles(Files) then
      MessageDlg('Add failed!'#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);

    ReloadFiles;
  finally
    Files.Free;
    SendDebugFmtEx_End(dlObject, '<- AddExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.UpdateActionImages;
var
  action: TAction;
begin
  //remove imageindex for disabled menuitems, because very ugly gray!
  for action in FActionList.Keys do
  begin
    if action.Enabled then
      action.ImageIndex := FActionList.Items[action]
    else
      action.ImageIndex := -1
  end;
end;

procedure TPlasticExpert.UpdateExecute(Sender: TObject);
var
  slFileList    : TStringList;
begin
  SendDebugFmtEx_Start(dlObject, '-> UpdateExecute', [], mtInformation);
  slFileList := TStringList.Create;
  try
    FActionStatus.Caption := 'Status: update pending...';

    ListFiles(slFileList);
    if not TPlasticEngine.UpdateFiles(slFileList, True) then
      MessageDlg('Update failed!'#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);
    ReloadFiles;
  finally
    slFileList.Free;
    SendDebugFmtEx_End(dlObject, '<- UpdateExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.UpdateMenu(aForced: boolean);
begin
  if aForced then
  begin
    FCurrentFile := '';
    FLastUpdate  := 0;
  end;
  GeneralUpdate(nil);
end;

procedure TPlasticExpert.DiffExecute(Sender: TObject);
var
  slFileList    : TStringList;
begin
  SendDebugFmtEx_Start(dlObject, '-> DiffExecute', [], mtInformation);
  slFileList := TStringList.Create;
  try
    FActionStatus.Caption := 'Status: diff pending...';

    //save editor changes first
    if Modified then ForceSaveModule;

    ListFiles(slFileList);
    if not TPlasticEngine.Diff(slFileList) then
      MessageDlg('Diff failed: '#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);
    ReloadFiles;
  finally
    slFileList.Free;
    SendDebugFmtEx_End(dlObject, '<- DiffExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.ListFiles(aFileList: TStrings);
var
  Serv            : IOTAModuleServices;
  iCounter        : Integer;
  sFile           : String;
begin
  aFileList.Clear;
  Serv := (BorlandIDEServices as IOTAModuleServices);
  if Serv.CurrentModule <> nil then
  begin
    for iCounter := 0 to Serv.CurrentModule.ModuleFileCount - 1 do
    begin
      sFile := Serv.CurrentModule.ModuleFileEditors[iCounter].FileName;
      SearchCorrespondingFiles(sFile, aFileList);
    end;
  end;
end;

procedure TPlasticExpert.LocalWriteableExecute(Sender: TObject);
var
  slFiles  : TStrings;
  s: string;
begin
  SendDebugFmtEx_Start(dlObject, '-> LocalWriteableExecute', [], mtInformation);
  slFiles := TStringList.Create;
  try
    FActionStatus.Caption := 'Status: making writeable...';

    //get all files
    ListFiles(slFiles);

    //remove readonly
    for s in slFiles do
      FileSetReadOnly(s, False);

    //save editor changes
    if Modified then ForceSaveModule;

    //reload
    ReloadFiles;
  finally
    slFiles.Free;
    SendDebugFmtEx_End(dlObject, '<- LocalWriteableExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.ReloadFiles;
var
  Serv        : IOTAModuleServices;
  ActSrv      : IOTAActionServices;
  sFile       : String;
  Editor      : IOTASourceEditor;
begin
  SendDebugFmtEx_Start(dlObject, '-> ReloadFiles', [], mtInformation);
  try
    Editor   := GetSourceEditor;

    if Supports(BorlandIDEServices, IOTAModuleServices, Serv) and
       Supports(BorlandIDEServices, IOTAActionServices, ActSrv) then
    begin
      if Serv.CurrentModule <> nil then
      begin
        sFile := Serv.CurrentModule.FileName;
        ActSrv.ReloadFile(sFile);
        //Editor.EditViews[0].Buffer.ClearUndo;
      end;
    end;
  finally
    SendDebugFmtEx_End(dlObject, '<- ReloadFiles done', [], mtInformation);
  end;
end;

function TPlasticExpert.GetFileInfo(psFileName: String; out pslInfo: TPlasticFileInfo;
  pbForce: Boolean): Boolean;
begin
  pslInfo := TPlasticEngine.GetFileInfo(psFileName);
  Result  := pslInfo <> nil;
end;

procedure TPlasticExpert.MenuExecute(Sender: TObject);
begin
//
end;

function TPlasticExpert.Modified: Boolean;
var
  Serv            : IOTAModuleServices;
begin
  Result := false;

  Serv := (BorlandIDEServices as IOTAModuleServices);
  if Serv.CurrentModule <> nil then
    Result := Serv.CurrentModule.CurrentEditor.Modified;
end;

function TPlasticExpert.GetModuleFile: string;
var
  Serv: IOTAModuleServices;
begin
  Result := '';

  Serv   := (BorlandIDEServices as IOTAModuleServices);
  {$IFDEF DELPHI2005}
  if P4Engine.IsServerUp and (Serv.CurrentModule <> nil) and (Serv.CurrentModule.FileName <> 'default.htm') then
  {$ELSE}
  if GPlasticEngine.IsServerUp and (Serv.CurrentModule <> nil) then
  {$ENDIF}
  begin
    Result := Serv.CurrentModule.FileName;
  end;
end;

function TPlasticExpert.GetModuleFileInfo(const aFile: string; out pslInfo: TPlasticFileInfo; pbForce: Boolean): Boolean;
begin
  Result := False;
  if aFile <> '' then
  begin
    Result := GetFileInfo(aFile, pslInfo, pbForce);

    //dproj file is used by IDE for the dpr file ("view source" option of project)
    //so if dproj is private (we do not checkin dproj at RBK because of programmers own local settings)
    //we check the status of real project file: .dpr :-)
    if (pslInfo <> nil) and (pslInfo.Status in [psUnknown, psPrivate]) and
       (LowerCase(ExtractFileExt(pslInfo.FileName)) = '.dproj') then
    begin
      if FileExists(ChangeFileExt(aFile, '.dpr')) then
      begin
        pslInfo.Free;
        Result := GetFileInfo( ChangeFileExt(aFile, '.dpr'), pslInfo, pbForce);
      end
      //not dpr found? then try dpk
      else if FileExists(ChangeFileExt(aFile, '.dpk')) then
      begin
        pslInfo.Free;
        Result := GetFileInfo( ChangeFileExt(aFile, '.dpk'), pslInfo, pbForce);
      end;
    end;

  end;
end;

procedure TPlasticExpert.HandleException(Sender: TObject);
var
  sError: string;
begin
  if Sender = nil then Exit;

  if Sender is Exception then
    HandleException(Sender as Exception)
  else
  begin
    sError := Format('Exception: %s'#13'Stack:'#13'%s',
                     [Sender.ClassName, GetLastStackAsString]);
    SendDebugEx(dlObject, sError, mtError);
    //MessageDlg(sError, Dialogs.mtError, [mbOK], 0);
  end;
end;

procedure TPlasticExpert.HandleException(E: Exception);
var
  sError: string;
begin
  if E = nil then Exit;
  sError := Format('%s: %s'#13'Stack:'#13'%s',
                   [E.ClassName, e.Message, GetLastStackAsString]);
  SendDebugEx(dlObject, sError, mtError);
  LogMessageToIDE(mtError, sError);
  //MessageDlg(sError, Dialogs.mtError, [mbOK], 0);
end;

procedure TPlasticExpert.DeleteExecute(Sender: TObject);
var
  slFiles : TStrings;
  Serv    : IOTAModuleServices;
  ActSrv  : IOTAActionServices;
  s: string;
begin
  SendDebugFmtEx_Start(dlObject, '-> DeleteExecute', [], mtInformation);
  slFiles := TStringList.Create;
  try
    FActionStatus.Caption := 'Status: delete pending...';

    ListFiles(slFiles);
    if not TPlasticEngine.DeleteFiles(slFiles) then
      MessageDlg('Delete failed!'#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);

    //force close module (in case of pending changes we skip "do you want to save") hmmm does not work?
    Serv := (BorlandIDEServices as IOTAModuleServices);
    if (Serv.CurrentModule <> nil) and
       (slFiles.IndexOf(Serv.CurrentModule.FileName) >= 0)
    then
      Serv.CurrentModule.CloseModule(True);

    //close other files (if any) and remove from project
    if Supports(BorlandIDEServices, IOTAActionServices, ActSrv) and
       (Serv.GetActiveProject <> nil) then
    begin
      for s in slFiles do
        Serv.GetActiveProject.RemoveFile(s);
      ActSrv.CloseFile(s);
    end;
  finally
    slFiles.Free;
    SendDebugFmtEx_End(dlObject, '<- DeleteExecute done', [], mtInformation);
  end;
end;

//procedure TPlasticExpert.OptionsExecute(Sender: TObject);
//begin
//  if FOptions.ShowDialogue then
//    RefreshShortcuts;
//end;

procedure TPlasticExpert.PlasticClientExecute(Sender: TObject);
begin
  SendDebugFmtEx_Start(dlObject, '-> PlasticClientExecute', [], mtInformation);
  try
    TPlasticEngine.ShowVisualClient;
  finally
    SendDebugFmtEx_End(dlObject, '<- PlasticClientExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.GeneralUpdate(Sender: TObject);
var
  slInfo : TPlasticFileInfo;
  sFile  : string;
  action : TAction;
begin
  try
    slInfo := nil;
    sFile  := GetModuleFile;

    //switched to other file? then reset
    if FCurrentFile <> sFile then
    begin
      FCurrentFile := sFile;
      FLastUpdate  := 0;
      FBusyWithUpdate := 0;
      FActionStatus.Caption := 'Status: pending (close menu for refresh)';
      for action in FActionList.Keys do
        if action <> FMenuPlastic.Action then
          action.Enabled := False;
      //always enabled
      FActionPlasticClient.Enabled := True;
      FActionReset.Enabled         := True;
    end;

    //already busy with async update?
    if (FBusyWithUpdate > 0) and
       (MilliSecondsBetween(Now, FBusyWithUpdate) < 5 * 1000) then Exit;
    FBusyWithUpdate := Now;

    //2x per s updaten is genoeg...
    if (FLastUpdate > 0) and
       (MilliSecondsBetween(Now, FLastUpdate) < 500) then Exit;
    FLastUpdate     := Now;

    RemoveReadonlyEditorFlag;

    //async update
    GAsyncThread.ExecuteASync(
        procedure
        begin
          SendDebugFmtEx_Start(dlObject, '-> GeneralUpdate, async', [], mtInformation);
          try
            try
              //get async the info
              GetModuleFileInfo(sFile, slInfo);
            finally
              //can make new call
              FBusyWithUpdate := 0;
            end;

            //update GUI in mainthread (threadsafe) again
            //if slInfo <> nil then
            TThread.Queue(nil,
                procedure
                begin
                  if (slInfo <> nil) then
                    FActionStatus.Caption := 'Status: ' + C_PlasticStatus[slInfo.Status]
                  else
                  begin
                    if not GPlasticEngine.IsServerUp then
                      FActionStatus.Caption := 'Status: Plastic SCM not found'
                    else
                      FActionStatus.Caption := 'Status: ? (close menu for refresh)';
                  end;
                  FActionStatus.Enabled   := True;
                  //FMenuPlastic.Caption   := C_Plastic_SCM + '(' + FActionStatus.Caption + ')';

            //      FActionRename.Enabled  := (slInfo <> nil) and (slInfo.Status in [psCheckedIn, psCheckedOut, psCheckedInAndLocalChanged]);
                  FActionRename.Enabled  := False; //does not work correctly yet
                  FActionAddAll.Enabled  := False;

                  FActionShelve.Enabled  := (slInfo <> nil) and (slInfo.Status in [psCheckedOut]);
                  FActionDelete.Enabled  := (slInfo <> nil) and (slInfo.Status in [psPrivate, psCheckedIn, psCheckedOut, psCheckedInAndLocalChanged]);
                  FActionConsole.Enabled := (slInfo <> nil);
                  FActionUpdate.Enabled  := (slInfo <> nil) and (slInfo.Status in [psCheckedIn, psCheckedOut, psCheckedInAndLocalChanged]);

                  FActionCheckout.Enabled   := (slInfo <> nil) and (slInfo.Status in [psCheckedIn, psCheckedInAndLocalChanged]);
                  FActionUncheckout.Enabled := (slInfo <> nil) and (slInfo.Status = psCheckedOut);
                  FActionCheckin.Enabled    := (slInfo <> nil) and (slInfo.Status = psCheckedOut);
                  FActionAdd.Enabled        := (slInfo <> nil) and (slInfo.Status = psPrivate);
                  FActionDiff.Enabled       := (slInfo <> nil) and (slInfo.Status in [psCheckedIn, psCheckedOut, psCheckedInAndLocalChanged]);
                  FActionUpdate.Enabled     := (slInfo <> nil) and (slInfo.Status in [psCheckedIn, psCheckedOut, psCheckedInAndLocalChanged]);

                  FActionWriteable.Enabled  := ((slInfo <> nil) and (slInfo.Status in [psCheckedIn, psCheckedOut])) or
                                               FileIsReadOnly(sFile);

                  UpdateActionImages;

                  slInfo.Free;
                end
              ); //TThread.Queue
          finally
            SendDebugFmtEx_End(dlObject, '<- GeneralUpdate, async, done', [], mtInformation);
          end;
        end
      );

  except
    on E:Exception do HandleException(E);
  end;
end;

procedure TPlasticExpert.AddAllExecute(Sender: TObject);
{
var
  Serv     : IOTAModuleServices;
  Proj     : IOTAProject;
  slFiles  : TStringList;
  ProjGrp  : IOTAProjectGroup;
  iCounter : Integer;
  }
begin
  MessageDlg('Not implemented yet', mtError, [mbOK], 0);
  {
  Serv := (BorlandIDEServices as IOTAModuleServices);

  slFiles := TStringList.Create;
  try
    Proj := nil;

    for iCounter := 0 to Serv.ModuleCount - 1 do
      begin
        if Supports(Serv.Modules[iCounter], IOTAProjectGroup, ProjGrp) then
          Proj := ProjGrp.ActiveProject;
        if Proj = nil then
          Supports(Serv.Modules[iCounter], IOTAProject, Proj);
      end;

    if Proj <> nil then
      begin
        Screen.Cursor := crHourGlass;
        try
          BuildFileList(Proj, slFiles);
        finally
          Screen.Cursor := crDefault;
        end;
        if slFiles.Count = 0 then
          MessageDlg('All files in this project are currently archived in Plastic.', mtInformation, [mbOK], 0)
        else
        begin
          //todo: add
        end;
    end;
  finally
    slFiles.Free;
  end;
  }
end;

procedure TPlasticExpert.RemoveAction(aAction: TAction; aToolbar: TToolbar);
var
  iCounter    : Integer;
  btnTool     : TToolButton;
begin
  for iCounter := aToolbar.ButtonCount - 1 downto 0 do
  begin
    btnTool := aToolbar.Buttons[iCounter];
    if btnTool.Action = aAction then
    begin
      aToolbar.Perform(CM_CONTROLCHANGE, WParam(btnTool), 0);
      btnTool.Free;
    end;
  end;
end;

procedure TPlasticExpert.RemoveActionFromToolbar(AAction: TAction);
var
  Services   : INTAServices;
begin
  if AAction = nil then Exit; 
  Services := (BorlandIDEServices as INTAServices);

  RemoveAction(AAction, Services.ToolBar[sCustomToolBar]);
  RemoveAction(AAction, Services.ToolBar[sDesktopToolBar]);
  RemoveAction(AAction, Services.ToolBar[sStandardToolBar]);
  RemoveAction(AAction, Services.ToolBar[sDebugToolBar]);
  RemoveAction(AAction, Services.ToolBar[sViewToolBar]);
end;

procedure TPlasticExpert.RemoveReadonlyEditorFlag;
var
  Serv: IOTAModuleServices;
begin
  Serv := (BorlandIDEServices as IOTAModuleServices);
  if Serv.CurrentModule <> nil then
  begin
    if Supports(Serv.CurrentModule.CurrentEditor, IOTAEditBuffer) and
       (Serv.CurrentModule.CurrentEditor as IOTAEditBuffer).IsReadOnly then
    begin
      (Serv.CurrentModule.CurrentEditor as IOTAEditBuffer).IsReadOnly := False;
      SendDebugFmt(dlObject, 'Readonly removed from editor of file: %s',[Serv.CurrentModule.FileName]);
    end
  end;
end;

procedure TPlasticExpert.RenameExecute(Sender: TObject);
var
  ActSrv  : IOTAActionServices;
  s, sNew, sExt, sNewFile: string;
  slFiles  : TStrings;
begin
  SendDebugFmtEx_Start(dlObject, '-> RenameExecute', [], mtInformation);
  slFiles := TStringList.Create;
  try
    ListFiles(slFiles);

    sNew := '';
    sNewFile := '';
    for s in slFiles do
    begin
      if sNew = '' then
      begin
        sNew := ExtractFileName(s);         //c:\temp\text.txt := text.txt
        sNew := ChangeFileExt(sNew,'');     //text
        if not InputQuery('Rename',
                          format('Enter new name for "%s":',[sNew]),
                          sNew) then Exit;
      end;

      sExt     := ExtractFileExt(s);                     //c:\temp\text.bak := .bak
      sNewFile := ExtractFilePath(s) + sNew + sExt;  //c:\temp\ + new + .bak

      TPlasticEngine.RenameFile(s, sNewFile);  //c:\temp\text.bak -> c:\temp\new.bak

      //oude bestand sluiten
      if Supports(BorlandIDEServices, IOTAActionServices, ActSrv) then
        ActSrv.CloseFile(s);
    end;

    //nieuw bestand (1e) openen
    if sNew <> '' then
    begin
      s := slFiles[0];
      sExt := ExtractFileExt(s);                     //c:\temp\text.bak := .bak
      sNewFile := ExtractFilePath(s) + sNew + sExt;  //c:\temp\ + new + .bak
      if Supports(BorlandIDEServices, IOTAActionServices, ActSrv) then
        ActSrv.OpenFile(s);
    end;
  finally
    slFiles.Free;
    SendDebugFmtEx_End(dlObject, '<- RenameExecute done', [], mtInformation);
  end;

end;

function TPlasticExpert.AddAction(psCaption, psHint, psName, psImageRes,
  psImageName: String; ExecuteEvent, UpdateEvent : TNotifyEvent): TAction;
var
  Service : INTAServices;
  bmpButton  : TBitmap;
begin
  Service := (BorlandIDEServices as INTAServices);

  Result := TAction.Create(Service.ActionList);
  with Result do
  begin
    ActionList := Service.ActionList;
    Category := C_Plastic_SCM;
    Caption := psCaption;
    Hint := psHint;
    Name := psName;
    if (psImageRes <> '') and (psImageName <> '') then
    begin
      bmpButton := TBitmap.Create;
      try
        try
          bmpButton.LoadFromResourceName(HInstance, psImageRes);
          ImageIndex := Service.AddMasked(bmpButton, clSilver, psImageName);
        except
          on E: Exception do
            MessageDlg(E.Message, mtError, [mbOK], 0);
        end;
      finally
        bmpButton.Free;
      end;
    end;
    OnExecute := ExecuteEvent;
    OnUpdate := UpdateEvent;
  end;

  FActionList.Add(Result, Result.ImageIndex);
end;

function TPlasticExpert.AddMenu(pAction: TAction): TMenuItem;
begin
  Result := TMenuItem.Create(FMenuPlastic);
  Result.Action := pAction;
  FMenuPlastic.Add(Result);
end;

{
procedure TPlasticExpert.RestoreBookmarks(AStorage: TSavedBookmarks);
var
  Editor    : IOTASourceEditor;
  iCounter  : Integer;
  MovePos,
  CurPos    : TOTAEditPos;
begin
  Editor := GetSourceEditor;
  if Editor <> nil then
  begin
    CurPos := Editor.EditViews[0].CursorPos;
    for iCounter := 0 to 9 do
    begin
      if (AStorage[iCounter].Line > 0) then
      begin
        MovePos.Col := AStorage[iCounter].CharIndex + 1;
        MovePos.Line := AStorage[iCounter].Line;
        Editor.EditViews[0].CursorPos := MovePos;
        Editor.EditViews[0].BookmarkRecord(iCounter);
      end;
    end;
    Editor.EditViews[0].CursorPos := CurPos;
    Editor.EditViews[0].MoveViewToCursor;
  end;
end;
}

procedure TPlasticExpert.ForceSaveModule;
var
  Serv     : IOTAModuleServices;
  slFiles  : TStrings;
  s: string;
begin
  slFiles := TStringList.Create;
  try
    //check all files
    ListFiles(slFiles);
    for s in slFiles do
    begin
      //remove readonly flag
      if FileIsReadOnly(s) then
        FileSetReadOnly(s, False);
    end;
  finally
    slFiles.Free;
  end;

  //save editor changes
  Serv := (BorlandIDEServices as IOTAModuleServices);
  if Serv.CurrentModule <> nil then
    Serv.CurrentModule.Save(False, True);
end;

procedure TPlasticExpert.ShelveExecute(Sender: TObject);
var
  slFiles  : TStrings;
begin
  SendDebugFmtEx_Start(dlObject, '-> ShelveExecute', [], mtInformation);
  slFiles := TStringList.Create;
  try
    FActionStatus.Caption := 'Status: shelve pending...';

    //save editor changes first
    if Modified then ForceSaveModule;

    ListFiles(slFiles);
    if not TPlasticEngine.ShelveFiles(slFiles) then
      MessageDlg('Shelve failed!'#13#13 + TPlasticEngine.GetLastError, mtError, [mbOK], 0);
  finally
    slFiles.Free;
    SendDebugFmtEx_End(dlObject, '<- ShelveExecute done', [], mtInformation);
  end;
end;

procedure TPlasticExpert.StatusExecute(Sender: TObject);
begin
  SendDebugFmtEx_Start(dlObject, '-> StatusExecute', [], mtInformation);
  try
    TPlasticEngine.ClearStatusCache;
    FActionStatus.Caption := 'Status: pending...';

    //refresh
    FLastUpdate  := 0;
    FCurrentFile := '';
    GeneralUpdate(nil);
  finally
    SendDebugFmtEx_End(dlObject, '<- StatusExecute done', [], mtInformation);
  end;
end;

{
function TPlasticExpert.StoreBookmarks(var AStorage: TSavedBookmarks): Boolean;
var
  Editor    : IOTASourceEditor;
  iCounter  : Integer;
begin
  Result := false;
  Editor := GetSourceEditor;

  if (Editor <> nil) and (Editor.EditViewCount > 0) then
  begin
    Result := true;
    for iCounter := 0 to 9 do
      AStorage[iCounter] := Editor.EditViews[0].BookmarkPos[iCounter];
  end;
end;
}

function TPlasticExpert.GetSourceEditor: IOTASourceEditor;
var
  Serv      : IOTAModuleServices;
  iCounter  : Integer;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Serv) then
  begin
    iCounter := 0;
    while (iCounter < Serv.CurrentModule.ModuleFileCount) and (Result = nil) do
    begin
      if not Supports(Serv.CurrentModule.ModuleFileEditors[iCounter], IOTASourceEditor, Result) then
        Inc(iCounter);
    end;
  end;
end;

{
procedure TPlasticExpert.RefreshShortcuts;
begin
  FActionAdd.ShortCut := FOptions.SC_AddNewArchive;

  FActionEdit.Shortcut := FOptions.SC_OpenForEdit;
  FActionSubmit.Shortcut := FOptions.SC_Submit;
  FActionRevert.Shortcut := FOptions.SC_Revert;
  FActionSync.Shortcut := FOptions.SC_Sync;
  FActionLock.Shortcut := FOptions.SC_Lock;
  FActionUnlock.Shortcut := FOptions.SC_Unlock;
  FActionDiff.Shortcut := FOptions.SC_DiffCurrent;
  FActionDiffHead.Shortcut := FOptions.SC_DiffHead;
  // FActionRevisionHistory.ShortCut := FOptions.SC_RevisionHistory;
  FActionP4VisualClient.ShortCut := FOptions.SC_VisualClient;
  FActionFileInfo.Shortcut := FOptions.SC_Properties;
  FActionOptions.Shortcut := FOptions.SC_Options;
  FActionAddAll.Shortcut := FOptions.SC_AddAll;
  FActionInfo.Shortcut := FOptions.SC_About;
end;
}

procedure TPlasticExpert.ConsoleExecute(Sender: TObject);
begin
  DebugConsole.Show;
end;

initialization
  try
    GPlasticExpert := TPlasticExpert.Create;
  except
    on E:Exception do HandleException(E);
  end;

finalization
  try
    GPlasticExpert.Free;
  except
    on E:Exception do HandleException(E);
  end;
  GPlasticExpert := nil;

end.
