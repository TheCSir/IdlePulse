using Wpf.Ui.Controls;

var exactNamesUsedInApp = new[]
{
    "SignOut24", "ArrowExit24", "DoorArrowRight24", "Power24"
};

var allSet = new HashSet<string>(Enum.GetNames<SymbolRegular>());
Console.WriteLine($"Total symbols: {allSet.Count}");
Console.WriteLine();

foreach (var name in exactNamesUsedInApp)
{
    var ok = allSet.Contains(name);
    Console.WriteLine($"{name,-24} {(ok ? "OK" : "INVALID")}");
}
