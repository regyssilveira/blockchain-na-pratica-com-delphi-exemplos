program Chapter04.Start;

{$APPTYPE CONSOLE}

uses
  System.SysUtils;

begin
  Writeln('ambiente_delphi=pronto');
  Writeln('bits_do_ponteiro=', SizeOf(Pointer) * 8);
  ExitCode := 0;
end.
