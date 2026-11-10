# Azure DevOps PowerShell Scripts

A collection of PowerShell scripts for managing Azure DevOps test plans, test suites, testcases, test execution results and reporting.

The scripts use the Azure DevOps REST API and provide reusable workflows for test management activities.

## Features

- Export test execution reports to Excel, including linked defects
- Copy and clone testcases between suites
- Select and filter testcases based on execution results
- Manage test suite structures
- Reuse common Azure DevOps functions across scripts

## 1. Prerequisites

- Windows PowerShell 5.1
- Access to the relevant Azure DevOps organization and project
- An Azure DevOps Personal Access Token (PAT) with appropriate permissions
- Internet access to Azure DevOps
- PowerShell `ImportExcel` module for Excel reports

## 2. Download the scripts

### Option A — Download ZIP (easiest)

1. Open the [GitHub repository](https://github.com/vogelconsult/Ado_Powershell_scripts).
2. Click **Code → Download ZIP**.
3. Extract the ZIP file to a local folder, for example `C:\ADO_API\ADO_API_Code`.
4. Open Windows PowerShell and navigate to the folder:

```powershell
cd C:\ADO_API\ADO_API_Code
```

### Option B — Clone with Git

If Git is installed:

```powershell
git clone https://github.com/vogelconsult/Ado_Powershell_scripts.git
cd Ado_Powershell_scripts
```

You can later retrieve updates with:

```powershell
git pull
```

## 3. Install required PowerShell modules

For Excel reporting, install `ImportExcel`:

```powershell
Install-Module ImportExcel -Scope CurrentUser
```

Verify installation:

```powershell
Get-Module ImportExcel -ListAvailable
```

The module can generate Excel files without Microsoft Excel being installed.

Other PowerShell modules may be required by individual scripts. Consult their documentation.

## 4. PowerShell execution policy

Check the current execution policy:

```powershell
Get-ExecutionPolicy -List
```

If downloaded scripts are blocked and your organization's security policy permits running them, use an approved method to unblock trusted files.

For example, to unblock a script you have inspected and trust:

```powershell
Unblock-File .\Export-TestReport.ps1
```

Alternatively, where organizational policy permits, the execution policy can be changed for the current PowerShell session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

This setting is temporary and is not retained after closing PowerShell.

Do not bypass restrictions enforced by your organization's IT security policies.

## 5. Create an Azure DevOps Personal Access Token (PAT)

1. Sign in to [Azure DevOps](https://dev.azure.com/).
2. Open **User settings → Personal access tokens**.
3. Select **New Token**.
4. Give the token a descriptive name, such as `ADO PowerShell Scripts`.
5. Select the relevant Azure DevOps organization.
6. Set a short expiration period.
7. Select the minimum scopes required by the operations you intend to perform.
8. Create the token and securely copy its value.

Permissions depend on the script. Reporting generally requires read access, while cloning and modifying testcases require additional write permissions.

Do not select Full Access unless specifically authorized and necessary.

**Security:** Never include PAT values in source files, Git commits, screenshots, support requests or shared documentation.

The scripts prompt for a PAT when required:

```text
Enter Azure DevOps PAT: ********
```

The token is used for authentication during script execution.

For more information, see [Microsoft's PAT documentation](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate).

## 6. Configure your Azure DevOps organization

The current library configuration is defined in:

`Shared/AdoConfiguration.ps1`

Verify that the configured organization and project match your Azure DevOps environment.

The initial distribution is configured for the intended project. Support for alternative configurations may be added later.

## 7. Run a script

### Example: Export an Excel test report

Navigate to the script folder:

```powershell
cd C:\ADO_API\Ado_Powershell_scripts
```

Start the report:

```powershell
.\Export-TestReport.ps1
```

When prompted, provide your PAT and Test Suite ID.

Alternatively, supply the Suite ID:

```powershell
.\Export-TestReport.ps1 -SuiteId 76360
```

By default, the report is saved as:

`TestReport_<SuiteId>.xlsx`

You can specify the output filename:

```powershell
.\Export-TestReport.ps1 `
    -SuiteId 76360 `
    -OutputPath ".\RegressionReport.xlsx"
```

The generated Excel workbook contains:

- **Summary:** Execution counts and pass rate
- **Test Results:** Individual testcases, outcomes and linked defects
- **Defects:** Defect ID, title, state, custom Bug Priority and testcase reference

### Other workflows

See [Script Reference](docs/ScriptReference.md) for the available scripts, parameters, examples and any operations that modify Azure DevOps data.

## 8. Validation

The repository includes validation scripts in `Tests`.

To run the offline reporting regression test:

```powershell
.\Tests\Test-ADOReportRefactor.ps1
```

A successful test should conclude with:

```text
ALL OFFLINE REPORT TESTS PASSED.
```

Offline validation does not confirm that your PAT has the required permissions or that Azure DevOps is accessible.

## 9. Important precautions

- Some scripts modify or create Azure DevOps work items and test suites.
- Verify source and destination suites before executing cloning or copying operations.
- Test modification scripts against dedicated test suites before using them on important test assets.
- Do not commit PATs, customer data or generated reports containing sensitive information.
- Respect your organization's Azure DevOps permissions and change management procedures.

## 10. Updating the scripts

If you downloaded a ZIP, download and extract the updated version, preserving your local configuration and any data files that you maintain separately.

If you cloned the repository:

```powershell
git pull
```

Review changes before running updated scripts, particularly those that modify Azure DevOps data.

---

**Maintained by:** Vogel Consult

**Platform:** Windows PowerShell 5.1 / Azure DevOps REST API
