# Script to create GitHub issues for merge optimization suggestions
# Requires GitHub CLI (gh) to be installed and authenticated
# Run: gh auth login (if not already authenticated)

# Get repository information
$repo = gh repo view --json nameWithOwner -q .nameWithOwner

if (-not $repo) {
    Write-Error "Could not determine repository. Make sure you're in a git repository and 'gh' is authenticated."
    exit 1
}

Write-Host "Creating issues in repository: $repo" -ForegroundColor Green

# Array of optimization suggestions
$issues = @(
    @{
        Title = "[Optimization] Eliminate Cursors for String Building"
        Body = @"
## Optimization Goal
Replace cursor-based operations with set-based operations for 30-70% performance improvement.

## Current Issue
The procedure uses two cursors (`pk_cursor` and `attr_cursor`) to iterate through columns and build ALTER TABLE statements. Cursors are slow and resource-intensive.

## Proposed Solution
Replace cursors with STRING_AGG (SQL Server 2017+) or FOR XML PATH (SQL Server 2012+) for set-based string aggregation.

## Expected Performance Gain
30-70% faster for tables with multiple columns

## Priority
🔴 High Priority - Immediate Impact

## Reference
See README-merge_optimization.md - Section 1
"@
        Labels = "enhancement,performance,high-priority"
    },
    @{
        Title = "[Optimization] Create Helper Function for Data Type Definition"
        Body = @"
## Optimization Goal
Extract duplicated data type building logic into a reusable function.

## Current Issue
The data type building logic is duplicated in two places (pk_cursor and attr_cursor), violating DRY principle.

## Proposed Solution
Create a scalar-valued function `dbo.fn_BuildDataTypeDefinition` to handle data type string generation.

## Benefits
- Code reusability
- Easier maintenance
- Consistent behavior
- Unit testable

## Priority
🟡 Medium Priority - Quality & Maintainability

## Reference
See README-merge_optimization.md - Section 2
"@
        Labels = "enhancement,refactoring,medium-priority"
    },
    @{
        Title = "[Optimization] Add Index to Table Variable"
        Body = @"
## Optimization Goal
Improve query performance on the @Columns table variable by adding indexes.

## Current Issue
The @Columns table variable is queried multiple times without an index, causing table scans.

## Proposed Solution
Add PRIMARY KEY and NONCLUSTERED INDEX to table variable definition.

## Expected Performance Gain
15-25% improvement when table has many columns

## Priority
🔴 High Priority - Immediate Impact

## Reference
See README-merge_optimization.md - Section 3
"@
        Labels = "enhancement,performance,high-priority"
    },
    @{
        Title = "[Optimization] Optimize String Concatenation"
        Body = @"
## Optimization Goal
Use modern T-SQL functions for efficient string concatenation.

## Current Issue
Multiple string concatenations using '+' operator can be inefficient and may cause implicit conversions.

## Proposed Solution
Use STRING_AGG (SQL Server 2017+) or STUFF with FOR XML PATH (SQL Server 2012+).

## Benefits
- Cleaner code
- Better performance
- No need for trailing character removal
- Handles NULL values better

## Priority
🔴 High Priority - Immediate Impact

## Reference
See README-merge_optimization.md - Section 4
"@
        Labels = "enhancement,performance,high-priority"
    },
    @{
        Title = "[Optimization] Add Comprehensive Error Handling"
        Body = @"
## Optimization Goal
Implement robust error handling with TRY-CATCH blocks.

## Current Issue
Limited error handling with basic RAISERROR. No transaction management or cleanup.

## Proposed Solution
Implement TRY-CATCH blocks with proper error propagation, logging, and context.

## Benefits
- Better error diagnosis
- Centralized error handling
- Error logging capability
- Cleaner error messages

## Priority
🔴 High Priority - Immediate Impact

## Reference
See README-merge_optimization.md - Section 5
"@
        Labels = "enhancement,reliability,high-priority"
    },
    @{
        Title = "[Optimization] Add Parameter Validation"
        Body = @"
## Optimization Goal
Add comprehensive input validation at procedure start.

## Current Issue
Minimal validation of input parameters and column name parameters.

## Proposed Solution
Add validation for:
- Schema existence
- Parameter null/empty checks
- SQL identifier validation (prevent SQL injection)

## Benefits
- Fail-fast approach
- Better error messages
- Prevents SQL injection
- Improves debugging experience

## Priority
🟡 Medium Priority - Quality & Maintainability

## Reference
See README-merge_optimization.md - Section 6
"@
        Labels = "enhancement,security,medium-priority"
    },
    @{
        Title = "[Optimization] Optimize Generated MERGE Statement"
        Body = @"
## Optimization Goal
Add query hints and transaction handling to generated MERGE procedures.

## Current Issue
Generated MERGE statement doesn't include performance hints or optimize for common scenarios.

## Proposed Solution
Add to generated procedures:
- HOLDLOCK hint to prevent race conditions
- Transaction wrapping for atomicity
- OPTION (RECOMPILE) for optimal execution plans
- Error handling in generated procedure

## Priority
⚪ Low Priority - Advanced Features

## Reference
See README-merge_optimization.md - Section 7
"@
        Labels = "enhancement,performance,low-priority"
    },
    @{
        Title = "[Optimization] Add Computed Columns for Metadata"
        Body = @"
## Optimization Goal
Use computed columns in table variable to reduce UPDATE operations.

## Current Issue
Column categorization happens via UPDATE statement after INSERT.

## Proposed Solution
Use computed columns in table variable definition when possible, with PERSISTED option.

## Benefits
- Reduces UPDATE operations
- Ensures data consistency
- Self-documenting code

## Priority
🟡 Medium Priority - Quality & Maintainability

## Reference
See README-merge_optimization.md - Section 8
"@
        Labels = "enhancement,refactoring,medium-priority"
    },
    @{
        Title = "[Configuration] Add Configuration Table for DW Column Names"
        Body = @"
## Optimization Goal
Create configuration table for enterprise-wide DW column name standardization.

## Current Issue
DW column names are passed as parameters, but defaults are hardcoded.

## Proposed Solution
Create `dbo.DataWarehouseConfiguration` table to centralize column naming standards.

## Benefits
- Centralized configuration
- Easy to change standards
- Multi-environment support
- Audit trail for configuration changes

## Priority
⚪ Low Priority - Advanced Features

## Status
⚠️ **NOT IMPLEMENTED** - Per decision, this optimization will not be implemented at this time.

## Reference
See README-merge_optimization.md - Section 9
"@
        Labels = "enhancement,configuration,low-priority,wontfix"
    },
    @{
        Title = "[Optimization] Add Caching for Repeated Metadata Queries"
        Body = @"
## Optimization Goal
Implement caching mechanism for frequently generated scripts.

## Current Issue
Metadata queries are executed every time the procedure runs.

## Proposed Solution
Create cache table `dbo.GeneratedScriptCache` with hash-based lookup for:
- Configuration parameters
- View structure
- Generated scripts

## Expected Performance Gain
95%+ performance boost on cache hits

## Priority
⚪ Low Priority - Advanced Features

## Reference
See README-merge_optimization.md - Section 10
"@
        Labels = "enhancement,performance,low-priority"
    },
    @{
        Title = "[Optimization] Add Support for Incremental/Batch Processing"
        Body = @"
## Optimization Goal
Add optional batch processing to generated MERGE procedures for large datasets.

## Current Issue
Generated MERGE processes all data at once, which can cause locking and performance issues with large datasets.

## Proposed Solution
Generate procedures with optional @BatchSize and @EnableBatching parameters for incremental processing.

## Benefits
- Reduces locking issues
- Better for large datasets
- Allows monitoring of progress
- Can be run during business hours with minimal impact

## Priority
⚪ Low Priority - Advanced Features

## Reference
See README-merge_optimization.md - Section 11
"@
        Labels = "enhancement,performance,low-priority"
    },
    @{
        Title = "[Optimization] Add Documentation Generation"
        Body = @"
## Optimization Goal
Add inline documentation to generated scripts.

## Current Issue
Generated code lacks inline documentation.

## Proposed Solution
Add header comments to generated scripts including:
- Generation timestamp
- Source view information
- Column counts and names
- Configuration details

## Priority
🟡 Medium Priority - Quality & Maintainability

## Reference
See README-merge_optimization.md - Section 12
"@
        Labels = "enhancement,documentation,medium-priority"
    },
    @{
        Title = "[Optimization] Add Logging and Monitoring"
        Body = @"
## Optimization Goal
Add execution logging for audit and performance tracking.

## Current Issue
No built-in logging or execution tracking.

## Proposed Solution
Create `dbo.ScriptGenerationLog` table to track:
- Execution times
- Duration metrics
- Column counts
- Success/failure status
- Error messages

## Priority
🟡 Medium Priority - Quality & Maintainability

## Reference
See README-merge_optimization.md - Section 13
"@
        Labels = "enhancement,monitoring,medium-priority"
    },
    @{
        Title = "[Testing] Performance Testing Framework"
        Body = @"
## Optimization Goal
Establish performance testing framework and benchmarks.

## Testing Scenarios
1. Small tables (< 10 columns)
2. Medium tables (10-50 columns)
3. Large tables (> 50 columns)
4. Wide tables (> 100 columns)
5. Complex data types (spatial, XML, hierarchyid)

## Metrics to Track
- Execution time
- Memory usage
- CPU usage
- Generated script length
- Cache hit rate (if caching is implemented)

## Priority
🟡 Medium Priority - Quality & Maintainability

## Reference
See README-merge_optimization.md - Section 14
"@
        Labels = "testing,performance,medium-priority"
    },
    @{
        Title = "[Documentation] SQL Server Version Compatibility Matrix"
        Body = @"
## Goal
Document feature compatibility across SQL Server versions.

## Scope
Maintain compatibility matrix for:
- STRING_AGG (SQL 2017+)
- FOR XML PATH (SQL 2012+)
- THROW (SQL 2012+)
- Table variable indexes (SQL 2012+)
- Other version-specific features

## Priority
🟡 Medium Priority - Quality & Maintainability

## Reference
See README-merge_optimization.md - Section 15
"@
        Labels = "documentation,compatibility,medium-priority"
    }
)

# Create issues
$createdIssues = @()

foreach ($issue in $issues) {
    Write-Host "`nCreating issue: $($issue.Title)" -ForegroundColor Cyan
    
    try {
        $result = gh issue create `
            --title $issue.Title `
            --body $issue.Body `
            --label $issue.Labels
        
        $createdIssues += @{
            Title = $issue.Title
            Url = $result
        }
        
        Write-Host "✓ Created: $result" -ForegroundColor Green
        Start-Sleep -Milliseconds 500  # Rate limiting
    }
    catch {
        Write-Host "✗ Failed to create issue: $($issue.Title)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Summary: Created $($createdIssues.Count) of $($issues.Count) issues" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

# Output created issues
$createdIssues | ForEach-Object {
    Write-Host "- $($_.Title)" -ForegroundColor White
    Write-Host "  $($_.Url)" -ForegroundColor Gray
}
