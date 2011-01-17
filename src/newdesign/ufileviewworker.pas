unit uFileViewWorker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  uFileView, uDisplayFile, uFile, uFileSource, uFileSorting, uFileProperty;

type
  TFileViewWorkerType = (fvwtNone,
                         fvwtFileListBuilder,
                         fvwtPropertiesRetriever);

  { TFileViewWorker }

  TFileViewWorker = class
  strict private
    FAborted: Boolean;
    FWorking: Boolean;
  protected
    FWorkerType: TFileViewWorkerType;
    function IsWorking: Boolean; virtual;
    procedure Execute; virtual; abstract;
  public
    constructor Create; virtual;
    procedure Abort;
    procedure Start;
    procedure StartParam(Params: Pointer);
    property Aborted: Boolean read FAborted;
    property Working: Boolean read IsWorking;
    property WorkerType: TFileViewWorkerType read FWorkerType;
  end;

  PRetrieveInfo = ^TRetrieveInfo;
  TRetrieveInfo = record
    FileIndex: Integer;
    RefFile: TFile;
    IconID: PtrInt;
  end;

  TSetFileListMethod = procedure (var NewDisplayFiles: TDisplayFiles;
                                  var NewFileSourceFiles: TFiles) of object;
  TUpdateFileMethod = procedure (const UpdateInfo: TRetrieveInfo) of object;

  { TFileListBuilder }

  TFileListBuilder = class(TFileViewWorker)
  private
    FTmpFileSourceFiles: TFiles;
    FTmpDisplayFiles: TDisplayFiles;
    FSetFileListMethod: TSetFileListMethod;

    // Data captured from the file view before start.
    FFileView: TFileView;
    FFileSource: IFileSource;
    FFileSourcesCount: Integer;
    FFileFilter: String;
    FCurrentPath: String;
    FThread: TThread;
    FSortings: TFileSortings;
    FFilePropertiesNeeded: TFilePropertiesTypes;

    {en
       Calls the update method with the new built lists.
       It is called from GUI thread.
    }
    procedure DoSetFileList;

  protected
    {en
       Retrieves file list from file source, sorts and creates a display file list.
       It may be run from a worker thread so it cannot access GUI directly.
    }
    procedure Execute; override;

  public
    constructor Create(AFileView: TFileView;
                       AThread: TThread;
                       AFilePropertiesNeeded: TFilePropertiesTypes;
                       ASetFileListMethod: TSetFileListMethod); reintroduce;

    {en
       Fills aFiles with files from aFileSourceFiles.
       Filters out any files that shouldn't be shown using aFileFilter.
    }
    class procedure MakeDisplayFileList(aFileSource: IFileSource;
                                        aFileSourceFiles: TFiles;
                                        aFiles: TDisplayFiles;
                                        aFileFilter: String);
  end;

  { TFilePropertiesRetriever }

  TFilePropertiesRetriever = class(TFileViewWorker)
  private
    FUpdateInfo: TRetrieveInfo;
    FRetrieveList: TFPList;
    FUpdateFileMethod: TUpdateFileMethod;
    FFileSource: IFileSource;
    FThread: TThread;
    FFilePropertiesNeeded: TFilePropertiesTypes;

    {en
       Updates file in the file view with new data from FUpdateInfo.
       It is called from GUI thread.
    }
    procedure DoUpdateFile;
    procedure DestroyRetrieveList;

  protected
    procedure Execute; override;

  public
    constructor Create(AFileSource: IFileSource;
                       AThread: TThread;
                       AFilePropertiesNeeded: TFilePropertiesTypes;
                       AUpdateFileMethod: TUpdateFileMethod;
                       var RetrieveList: TFPList);
    destructor Destroy; override;
  end;

implementation

uses
  LCLProc,
  uFileSourceListOperation, uFileSourceOperationTypes, uOSUtils, uDCUtils,
  uGlobs, uMasks, uPixMapManager, uFileSourceProperty;

{ TFileViewWorker }

constructor TFileViewWorker.Create;
begin
  FAborted := False;
  // Set Working=True on creation because these workers are usually scheduled
  // to run by a non-main thread.
  FWorking := True;
  FWorkerType := fvwtNone;
end;

procedure TFileViewWorker.Abort;
begin
  FAborted := True;
end;

procedure TFileViewWorker.Start;
begin
  Execute; // virtual call
  FWorking := False;
end;

procedure TFileViewWorker.StartParam(Params: Pointer);
begin
  Execute; // virtual call
  FWorking := False;
end;

function TFileViewWorker.IsWorking: Boolean;
begin
  Result := FWorking;
end;

{ TFileListBuilder }

constructor TFileListBuilder.Create(AFileView: TFileView;
                                    AThread: TThread;
                                    AFilePropertiesNeeded: TFilePropertiesTypes;
                                    ASetFileListMethod: TSetFileListMethod);
begin
  inherited Create;

  FTmpFileSourceFiles := nil;
  FTmpDisplayFiles := nil;
  FWorkerType := fvwtFileListBuilder;

  // Copy these parameters while it's still safe to access them from the main thread.
  FFileView             := AFileView;
  FFileSource           := AFileView.FileSource;
  FFileSourcesCount     := AFileView.FileSourcesCount;
  FFileFilter           := AFileView.FileFilter;
  FCurrentPath          := AFileView.CurrentPath;
  FThread               := AThread;
  FSortings             := CloneSortings(AFileView.Sorting);
  FFilePropertiesNeeded := AFilePropertiesNeeded;
  FSetFileListMethod    := ASetFileListMethod;
end;

procedure TFileListBuilder.Execute;
var
  AFile: TFile;
  ListOperation: TFileSourceListOperation;
  i: Integer;
  HaveUpDir: Boolean = False;
begin
  try
    if Aborted then
      Exit;

    if fsoList in FFileSource.GetOperationsTypes then
    begin
      ListOperation := FFileSource.CreateListOperation(FCurrentPath) as TFileSourceListOperation;
      if Assigned(ListOperation) then
        try
          ListOperation.AssignThread(FThread);
          ListOperation.Execute;
          FTmpFileSourceFiles := ListOperation.ReleaseFiles;
        finally
          FreeAndNil(ListOperation);
        end;
    end;

    {$IFDEF timeFileView}
    DebugLn('Loaded files   : ' + IntToStr(DateTimeToTimeStamp(Now - startTime).Time));
    {$ENDIF}

    if Aborted then
      Exit;

    if Assigned(FTmpFileSourceFiles) then
    begin
      TFileView.Sort(FTmpFileSourceFiles, FSortings);

      // Check if up-dir '..' is present.
      // If it is present it will usually be the first file.
      for i := 0 to FTmpFileSourceFiles.Count - 1 do
      begin
        if FTmpFileSourceFiles[i].Name = '..' then
        begin
          HaveUpDir := True;
          Break;
        end;
      end;

      if (not HaveUpDir) and
         ((not FFileSource.IsPathAtRoot(FCurrentPath)) or
          // Add '..' to go to higher level file source, if there is more than one.
          (FFileSourcesCount > 1)) then
      begin
        AFile := FFileSource.CreateFileObject(FCurrentPath);
        AFile.Name := '..';
        if fpAttributes in AFile.SupportedProperties then
          AFile.Attributes := faFolder;
        FTmpFileSourceFiles.Insert(AFile, 0);
      end;
    end;

    if Aborted then
      Exit;

    {$IFDEF timeFileView}
    DebugLn('Sorted files   : ' + IntToStr(DateTimeToTimeStamp(Now - startTime).Time));
    {$ENDIF}

    // Make display file list from file source file list.
    FTmpDisplayFiles := TDisplayFiles.Create;
    MakeDisplayFileList(FFileSource, FTmpFileSourceFiles, FTmpDisplayFiles, FFileFilter);

    {$IFDEF timeFileView}
    DebugLn('Made disp. list: ' + IntToStr(DateTimeToTimeStamp(Now - startTime).Time));
    {$ENDIF}

    if Aborted then
      Exit;

    // Loading file list is complete. Update grid with the new file list.
    TThread.Synchronize(FThread, @DoSetFilelist);

    {$IFDEF timeFileView}
    DebugLn('Grid updated   : ' + IntToStr(DateTimeToTimeStamp(Now - startTime).Time));
    {$ENDIF}

  finally
    {$IFDEF timeFileView}
    DebugLn('Finished       : ' + IntToStr(DateTimeToTimeStamp(Now - startTime).Time));
    {$ENDIF}

    FreeThenNil(FTmpDisplayFiles);
    FreeThenNil(FTmpFileSourceFiles);
  end;
end;

class procedure TFileListBuilder.MakeDisplayFileList(
                  aFileSource: IFileSource;
                  aFileSourceFiles: TFiles;
                  aFiles: TDisplayFiles;
                  aFileFilter: String);
var
  AFile: TDisplayFile;
  i: Integer;
  invalidFilter: Boolean = False;
  sFilterNameNoExt,
  sFilterExt,
  localFilter: String;
begin
  aFiles.Clear;

  if Assigned(aFileSourceFiles) then
  begin
    // Prepare filter string based on options.
    if aFileFilter <> EmptyStr then
    begin
      localFilter := aFileFilter;
      if Pos('.', aFileFilter) <> 0 then
        begin
          sFilterNameNoExt := ExtractOnlyFileName(localFilter);
          sFilterExt := ExtractFileExt(localFilter);
          if not gQuickSearchMatchBeginning then
            sFilterNameNoExt := '*' + sFilterNameNoExt;
          if not gQuickSearchMatchEnding then
            sFilterNameNoExt := sFilterNameNoExt + '*';
          localFilter := sFilterNameNoExt + sFilterExt + '*';
        end
      else
        begin
          if not gQuickSearchMatchBeginning then
            localFilter := '*' + localFilter;
          localFilter := localFilter + '*';
        end;
    end;

    for i := 0 to aFileSourceFiles.Count - 1 do
    begin
      if gShowSystemFiles = False then
      begin
        if aFileSourceFiles[i].IsSysFile and (aFileSourceFiles[i].Name <> '..') then
          Continue;
      end;

      // Ignore list
      if gIgnoreListFileEnabled then
      begin
        if MatchesMaskListEx(aFileSourceFiles[i], glsIgnoreList) then Continue;
      end;

      // Filter files.
      if (aFileFilter <> EmptyStr) and (invalidFilter = False) then
      begin
        try
          if (aFileSourceFiles[i].Name <> '..') and
             (aFileSourceFiles[i].Name <> '.') and

             // Don't filter directories.
             not (aFileSourceFiles[i].IsDirectory or
                  aFileSourceFiles[i].IsLinkToDirectory) and

             not MatchesMask(UTF8LowerCase(aFileSourceFiles[i].Name),
                             UTF8LowerCase(localFilter))
          then
            Continue;

        except
          on EConvertError do
            invalidFilter := True;
        end;
      end;

      AFile := TDisplayFile.Create(aFileSourceFiles[i]);

      if gShowIcons <> sim_none then
      begin
        AFile.IconID := PixMapManager.GetIconByFile(AFile.TheFile,
                                                    fspDirectAccess in aFileSource.Properties,
                                                    not gLoadIconsSeparately);
      end;

      aFiles.Add(AFile);
    end;
  end;
end;

procedure TFileListBuilder.DoSetFileList;
begin
  if not Aborted and Assigned(FSetFileListMethod) then
    FSetFileListMethod(FTmpDisplayFiles, FTmpFileSourceFiles);
end;

{ TFilePropertiesRetriever }

constructor TFilePropertiesRetriever.Create(AFileSource: IFileSource;
                                            AThread: TThread;
                                            AFilePropertiesNeeded: TFilePropertiesTypes;
                                            AUpdateFileMethod: TUpdateFileMethod;
                                            var RetrieveList: TFPList);
begin
  FWorkerType           := fvwtPropertiesRetriever;
  FRetrieveList         := RetrieveList;
  RetrieveList          := nil;
  FFileSource           := AFileSource;
  FThread               := AThread;
  FFilePropertiesNeeded := AFilePropertiesNeeded;
  FUpdateFileMethod     := AUpdateFileMethod;
end;

destructor TFilePropertiesRetriever.Destroy;
begin
  DestroyRetrieveList;
  inherited Destroy;
end;

procedure TFilePropertiesRetriever.Execute;
var
  i: Integer;
begin
  try
    for i := 0 to FRetrieveList.Count - 1 do
    begin
      if Aborted then
        Exit;

      FUpdateInfo := PRetrieveInfo(FRetrieveList[i])^;
      if FFileSource.CanRetrieveProperties(FUpdateInfo.RefFile, FFilePropertiesNeeded) then
        FFileSource.RetrieveProperties(FUpdateInfo.RefFile, FFilePropertiesNeeded);

      if FUpdateInfo.IconID = -1 then
        FUpdateInfo.IconID := PixMapManager.GetIconByFile(
            FUpdateInfo.RefFile,
            fspDirectAccess in FFileSource.Properties,
            True);

      TThread.Synchronize(FThread, @DoUpdateFile);
    end;

  finally
    DestroyRetrieveList;
  end;
end;

procedure TFilePropertiesRetriever.DoUpdateFile;
begin
  if not Aborted and Assigned(FUpdateFileMethod) then
    FUpdateFileMethod(FUpdateInfo);
end;

procedure TFilePropertiesRetriever.DestroyRetrieveList;
var
  i: Integer;
begin
  if Assigned(FRetrieveList) then
  begin
    for i := 0 to FRetrieveList.Count - 1 do
    begin
      PRetrieveInfo(FRetrieveList[i])^.RefFile.Free;
      Dispose(PRetrieveInfo(FRetrieveList[i]));
    end;
    FreeAndNil(FRetrieveList);
  end;
end;

end.

