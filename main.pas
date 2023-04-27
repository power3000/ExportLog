unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  DateTimePicker, Windows, ShlObj, IniFiles, DateUtils;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    cbSplitByDT: TCheckBox;
    etDateOn: TDateTimePicker;
    etDateOff: TDateTimePicker;
    etStation: TEdit;
    edJtdxLog: TEdit;
    edExportFile: TEdit;
    etOPCallSign: TEdit;
    GroupBox1: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    OpenDialog1: TOpenDialog;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure cbSplitByDTChange(Sender: TObject);
    procedure etOPCallSignChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
  private
    procedure LoadSettings(Sender: TObject);
    procedure SaveSettings(Sender: TObject);

  public

  end;

var
  Form1: TForm1;
  INI                  : TINIFile;
  OPCallSign           : String;
  ADIFile              : String;

  AFormatSettings: TFormatSettings;
const
  DateFormatChars = 'yyyymmdd';
  C_DB_SECTION = 'OP-INFO';


implementation

{$R *.lfm}

{ TForm1 }
procedure TForm1.LoadSettings(Sender: TObject);
begin
  INI := TINIFile.Create('config.ini');
  etOPCallSign.Text       := INI.ReadString(C_DB_SECTION,'OPCallSign','BD5XX');
  edJtdxLog.Text          := INI.ReadString(C_DB_SECTION,'ADIFile','');
  etStation.Text :=   INI.ReadString(C_DB_SECTION,'StationCallSign','B5CRA');
  // Load the configuration settings from the INI file
  // and set the state of the cbSplitByDT checkbox accordingly
  cbSplitByDT.Checked := INI.ReadBool(C_DB_SECTION, 'SplitByDT', False);

end;

procedure TForm1.SaveSettings(Sender: TObject);
begin
  INI := TINIFile.Create('config.ini');

  INI.WriteString(C_DB_SECTION,'StationCallSign',etStation.Text);
  INI.WriteString(C_DB_SECTION,'OPCallSign',etOPCallSign.Text);
  INI.WriteString(C_DB_SECTION,'ADIFile',edJtdxLog.Text);
  // Save the state of the cbSplitByDT checkbox
  INI.WriteBool(C_DB_SECTION, 'SplitByDT', cbSplitByDT.Checked);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin

  // Find wsjtx_log.adi from install dir
  LoadSettings(Sender);

  //
  //etDateOn.DateFormat:= DateFormatChars;
  //etDateOff.DateFormat := DateFormatChars;

  etDateOn.Date := now;
  etDateOff.Date := now;
  edExportFile.Text := etStation.Text + ' (OP ' + etOPCallSign.Text  + ') ' + FormatDateTime( DateFormatChars, now ) + '.adi';

end;


procedure TForm1.Button3Click(Sender: TObject);
var
  infile, outfile :TextFile;
  logitem, str:string;
  QsqDate: TDate;
  AFormat: TFormatSettings;
  op_chunk,new_operator,station_chunk,new_station_callsign: string;
begin

  AFormat.ShortDateFormat := 'yyyymmdd';
  AFormat.DateSeparator := '/';

  if  etStation.Text = ''  then
  begin
     ShowMessage('台站呼号不能为空！');
     Exit;
  end;

  if  etOPCallSign.Text = ''  then
  begin
     ShowMessage('OP呼号不能为空！');
     Exit;
  end;

  // Check jtdx  adi file
  if not FileExists( edJtdxLog.Text ) then
  begin
     MessageDlg('File: ' + edJtdxLog.Text  +
                  ' not found', mtError, [mbOk], 0);
  end;

  try
     AssignFile( infile, edJtdxLog.Text);
     AssignFile( outfile, edExportFile.Text);

     Rewrite(outfile);

     Reset(infile);

     // read header
     // <EOH>
     logitem := '';
     repeat
       Readln(infile, str);
       // Check date
       logitem := logitem + str;
     until( EOF(infile) or ( str.ToLower.IndexOf('<eoh>') <> -1));


     // Write adi file header
     WriteLn(outfile, logitem);
     WriteLn(outfile, chr(13)+chr(10));

     // read record
     repeat
       logitem := '' ;
       repeat
         Readln(infile, str);
         logitem := logitem + str;
       until( EOF(infile) or (str.ToLower.IndexOf('<eor>') <> -1));


       // Check date
       if Pos('<qso_date:8>', logitem.ToLower) > 0 then
       begin
          str := Copy ( logitem, Pos('<qso_date:8>', logitem.ToLower) + 12, 8);
          str.Insert(4,'/');
          str.Insert(7,'/');

          if TryStrToDate(str, QsqDate, AFormat) then
            QsqDate := StrToDate(str, AFormat )
          else
            Continue;

        // Check if cbSplitByDT is checked
        if cbSplitByDT.Checked then
        begin
          // If cbSplitByDT is checked, check if the QSO date is within the specified range
          if (CompareDate(QsqDate, etDateOn.Date) >= 0) and (CompareDate(QsqDate, etDateOff.Date) <= 0) then
          begin
            
            // Check if the line contains the station_callsign string
            if Pos('<station_callsign:', logitem) > 0 then
            begin
              // Extract the station_chunk string
              station_chunk := Copy(logitem, Pos('<station_callsign:', logitem), Length(logitem));
              station_chunk := Copy(station_chunk, 1, Pos(' ', station_chunk));
              
              // Replace the station_chunk string with the new station_callsign string
              new_station_callsign := '<station_callsign:' + IntToStr(Length(etStation.Text)) + '>' + etStation.Text +' ';
              logitem := StringReplace(logitem, station_chunk, new_station_callsign, []);
            end;
  
            // insert op information
            // <OPERATOR:6>BG5UER <OWNER_CALLSIGN:6>BG5UER <STATION_CALLSIGN:6>BG5UER
            // Check if exist operator filed
            if Pos('operator', logitem) = 0 then
              Write(outfile, '<operator:' + IntToStr(Length(etOPCallSign.Text)) + '>'+ etOPCallSign.Text + ' ')
            else
            begin

              // if find operator then ask if to replace it
              //if MessageDlg('Find <operator> in the logfile, replace it?', mtConfirmation, [mbOK, mbCancel], 0) = mrOK then
              begin
                // Extract the op_chunk string
                op_chunk := Copy(logitem, Pos('<operator:', logitem), Length(logitem));
                op_chunk := Copy(op_chunk, 1, Pos(' ', op_chunk));
                
                // Replace the op_chunk string with the new operator string
                new_operator := '<operator:' + IntToStr(Length(etOPCallSign.Text)) + '>' + etOPCallSign.Text + ' ';
                logitem := StringReplace(logitem, op_chunk, new_operator, []);
                
                WriteLn(outfile, logitem);
              end
            end;

            WriteLn(outfile, logitem);
            //WriteLn(outfile, chr(13)+chr(10));
          end;
        end
        else
        begin
          // Check if the line contains the station_callsign string
          if Pos('<station_callsign:', logitem) > 0 then
          begin
            // Extract the station_chunk string
            station_chunk := Copy(logitem, Pos('<station_callsign:', logitem), Length(logitem));
            station_chunk := Copy(station_chunk, 1, Pos(' ', station_chunk));
            
            // Replace the station_chunk string with the new station_callsign string
            new_station_callsign := '<station_callsign:' + IntToStr(Length(etStation.Text)) + '>' + etStation.Text + ' ';
            logitem := StringReplace(logitem, station_chunk, new_station_callsign, []);
          end;

          // If cbSplitByDT is not checked, process the QSO directly
          // insert op information
          // <OPERATOR:6>BG5UER <OWNER_CALLSIGN:6>BG5UER <STATION_CALLSIGN:6>BG5UER
          // Check if exist operator filed
          if Pos('operator', logitem) = 0 then
            Write(outfile, '<operator:' + IntToStr(Length(etOPCallSign.Text)) + '>'+ etOPCallSign.Text + ' ')
          else
          begin
            // if find operator then ask if to replace it
            //if MessageDlg('Find <operator> in the logfile, replace it?', mtConfirmation, [mbOK, mbCancel], 0) = mrOK then
            begin
              // Extract the op_chunk string
              op_chunk := Copy(logitem, Pos('<operator:', logitem), Length(logitem));
              op_chunk := Copy(op_chunk, 1, Pos(' ', op_chunk));
              
              // Replace the op_chunk string with the new operator string
              new_operator := '<operator:' + IntToStr(Length(etOPCallSign.Text)) + '>' + etOPCallSign.Text + ' ';
              logitem := StringReplace(logitem, op_chunk, new_operator, []);
              
              WriteLn(outfile, logitem);
            end
          end;

          WriteLn(outfile, logitem);
          //WriteLn(outfile, chr(13)+chr(10));
        end;
       end;


     until(EOF(infile));

     CloseFile(infile);
     CloseFile(outfile);

   except
     on E: EInOutError do
     begin
         ShowMessage('File handling error occurred. Details: '+E.ClassName+'/'+E.Message);
     end;
   end;

   ShowMessage('导出日志成功！');

end;

procedure TForm1.cbSplitByDTChange(Sender: TObject);
begin

end;

procedure TForm1.etOPCallSignChange(Sender: TObject);
begin
    edExportFile.Text := etStation.Text + '(OP ' + etOPCallSign.Text  + ') ' + FormatDateTime( DateFormatChars, now ) + '.adi';

end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  SaveSettings(Sender);
end;


procedure TForm1.Button1Click(Sender: TObject);
var
  FilePath: array [0..MAX_PATH] of char;

begin
  // Get the program filepath
  FilePath := GetCurrentDir;
  OpenDialog1.InitialDir := FilePath;

  if OpenDialog1.Execute  then
  begin
    edJtdxLog.Text := OpenDialog1.FileName;
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  if OpenDialog1.Execute  then
  begin
    edExportFile.Text := OpenDialog1.FileName;
  end;

end;

end.

