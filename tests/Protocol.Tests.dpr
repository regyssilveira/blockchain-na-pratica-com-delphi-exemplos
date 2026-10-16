program Protocol.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.Init,
  Blockchain.Primitives in '..\src\Blockchain.Primitives.pas',
  Blockchain.Ethereum in '..\src\Blockchain.Ethereum.pas',
  Blockchain.Primitives.Tests in 'Blockchain.Primitives.Tests.pas',
  Blockchain.Ethereum.Tests in 'Blockchain.Ethereum.Tests.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile));
    Results := Runner.Execute;
    System.ExitCode := TDUnitX.ExitCodeFor(Results);
  except
    on Error: Exception do
    begin
      System.Writeln(Error.ClassName, ': ', Error.Message);
      System.ExitCode := 1;
    end;
  end;
end.
