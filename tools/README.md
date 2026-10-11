Run the package regression checks from the repository root with Windows PowerShell:

```powershell
powershell.exe -NoProfile -File .\tools\Test-PackageRuntime.ps1
```

Pass `-BuiltDll` with a compiled DragoonCapes DLL to repeat the checks with the actual assembly and its portable PDB. The checks use owned temporary game and plugin directories under the repository's `bin\PackageRegression` folder. They verify Release ZIP contents, Debug copies, repeated packaging, the actual asset and translation loading methods, optional symbols, and failure handling.

These checks do not launch Valheim or establish in-game acceptance. Compilation must use fresh references from the target game version; bundled older game libraries can take precedence over supplied references in MSBuild.
