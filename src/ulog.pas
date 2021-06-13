{
   Double Commander
   -------------------------------------------------------------------------
   This unit contains log write functions

   Copyright (C) 2008-2019 Alexander Koblov (alexx2000@mail.ru)

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program. If not, see <http://www.gnu.org/licenses/>.
}

unit uLog;

{$mode objfpc}{$H+}

interface

uses
  Classes;
  
type
  TLogMsgType = (lmtInfo, lmtSuccess, lmtError);

function GetActualLogFileName: String;
procedure ShowLogWindow(bShow: Boolean);
procedure LogWrite(const sText: String; LogMsgType: TLogMsgType = lmtInfo; bForce: Boolean = False; bLogFile: Boolean = True); overload;
procedure LogWrite({%H-}Thread: TThread; const sText: String; LogMsgType: TLogMsgType = lmtInfo; bForce: Boolean = False; bLogFile: Boolean = True); overload;

implementation

uses
  SysUtils, Forms, FileUtil, fMain, uDebug, uGlobs, uFileProcs, DCOSUtils, uDCUtils;

type
  PLogMessage = ^TLogMessage;
  TLogMessage = record
    Message: String;
    case Boolean of
      True: (ObjectType: TObject);
      False: (MessageType: TLogMsgType);
  end;

type

  { TLogWriter }

  TLogWriter = class
  private
    FMutex: TRTLCriticalSection;
  private
    procedure ShowLogWindow;
    procedure WriteInMainThread(Data: PtrInt);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Write(const sText: String; LogMsgType: TLogMsgType; bForce, bLogFile: Boolean);
  end;

var
  LogWriter: TLogWriter;

function GetActualLogFileName: String;
begin
  Result:= ReplaceEnvVars(gLogFileName);

  if gLogFileWithDateInName then
  begin
    Result:= Copy(Result, 1, Length(Result) - Length(ExtractFileExt(Result))) +
                   '_' + ReplaceEnvVars(EnvVarTodaysDate) + ExtractFileExt(Result);
  end;
end;

procedure ShowLogWindow(bShow: Boolean);
begin
  if Assigned(frmMain) then frmMain.ShowLogWindow(PtrInt(bShow));
end;

procedure LogWrite(const sText: String; LogMsgType: TLogMsgType; bForce, bLogFile: Boolean); inline;
begin
  LogWriter.Write(sText, LogMsgType, bForce, bLogFile);
end;

procedure LogWrite(Thread: TThread; const sText: String; LogMsgType: TLogMsgType; bForce: Boolean; bLogFile: Boolean); inline;
begin
  LogWriter.Write(sText, LogMsgType, bForce, bLogFile);
end;

function StringListSortCompare(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result:= CompareText(List[Index2], List[Index1]);
end;

{ TLogWriter }

procedure TLogWriter.ShowLogWindow;
begin
  frmMain.ShowLogWindow(PtrInt(True));
end;

procedure TLogWriter.WriteInMainThread(Data: PtrInt);
var
  Msg: PLogMessage absolute Data;
begin
  if not Application.Terminated then
  begin
    with fMain.frmMain do
    try
      seLogWindow.CaretY:= seLogWindow.Lines.AddObject(Msg^.Message, Msg^.ObjectType) + 1;
    finally
      Dispose(Msg);
    end;
  end;
end;

constructor TLogWriter.Create;
begin
  InitCriticalSection(FMutex);
end;

destructor TLogWriter.Destroy;
begin
  inherited Destroy;
  DoneCriticalsection(FMutex);
end;

procedure TLogWriter.Write(const sText: String; LogMsgType: TLogMsgType; bForce, bLogFile: Boolean);
var
  Index: Integer;
  Message: String;
  hLogFile: THandle;
  LogMessage: PLogMessage;
  ActualLogFileName: String;
  ALogFileList: TStringList;
begin
  if Assigned(fMain.frmMain) and (bForce or gLogWindow) then
  begin
    if bForce and (not frmMain.seLogWindow.Visible) then
    begin
      if GetCurrentThreadId = MainThreadID then
        Self.ShowLogWindow
      else
        TThread.Synchronize(nil, @Self.ShowLogWindow);
    end;
    New(LogMessage);
    LogMessage^.Message:= sText;
    LogMessage^.MessageType:= LogMsgType;
    Application.QueueAsyncCall(@WriteInMainThread, {%H-}PtrInt(LogMessage));
  end;

  if gLogFile and bLogFile then
  begin
    EnterCriticalsection(FMutex);
    try
      ActualLogFileName:= GetActualLogFileName;
      Message:= Format('%s %s', [DateTimeToStr(Now), sText]);

      if mbFileExists(ActualLogFileName) then
        hLogFile:= mbFileOpen(ActualLogFileName, fmOpenWrite)
      else begin
        hLogFile:= mbFileCreate(ActualLogFileName);
        if gLogFileCount > 0 then
        begin
          ALogFileList:= FindAllFiles(ExtractFileDir(ActualLogFileName), '*_????-??-??' + ExtractFileExt(ActualLogFileName), False);
          ALogFileList.CustomSort(@StringListSortCompare);
          for Index:= gLogFileCount to ALogFileList.Count - 1 do
          begin
            mbDeleteFile(ALogFileList[Index]);
          end;
          ALogFileList.Free;
        end;
      end;

      if (hLogFile = feInvalidHandle) then
        DCDebug('LogWrite: ' + mbSysErrorMessage)
      else begin
        FileSeek(hLogFile, 0, soFromEnd);
        FileWriteLn(hLogFile, Message);
        FileClose(hLogFile);
      end;
      DCDebug(Message);
    finally
      LeaveCriticalsection(FMutex);
    end;
  end;
end;

initialization
  LogWriter:= TLogWriter.Create;

finalization
  LogWriter.Free;

end.
