# Flusso di Sincronizzazione Landing Zone - Documentazione Tecnica

## Indice
- [Panoramica](#panoramica)
- [Architettura](#architettura)
- [Struttura Pacchetto SSIS](#struttura-pacchetto-ssis)
- [Passi di Sincronizzazione](#passi-di-sincronizzazione)
- [Pattern di Implementazione](#pattern-di-implementazione)
- [Gestione Errori](#gestione-errori)
- [Ottimizzazione Prestazioni](#ottimizzazione-prestazioni)
- [Esempi](#esempi)
- [Migliori Pratiche](#migliori-pratiche)
- [Monitoraggio e Logging](#monitoraggio-e-logging)

## Panoramica

Questo documento descrive l'implementazione tecnica del **flusso di sincronizzazione** che carica i dati dai sistemi sorgente nella Landing zone utilizzando **SQL Server Integration Services (SSIS)**. Ogni tabella Landing ha un pacchetto SSIS dedicato che implementa un pattern consistente e ripetibile per rilevare e applicare i cambiamenti.

### Scopo

Il flusso di sincronizzazione assicura che:
- Le tabelle Landing siano repliche fedeli delle tabelle sorgente
- I cambiamenti siano rilevati efficientemente usando confronto basato su hash
- Tutti i cambiamenti siano tracciati con metadati temporali
- I record eliminati siano gestiti con pattern soft-delete
- Il processo sia idempotente e possa essere ripetuto in sicurezza

### Principi di Progettazione

1. **Pacchetto-per-Tabella**: Ogni tabella Landing ha il proprio pacchetto SSIS
2. **CDC Basato su Hash**: Cambiamenti rilevati confrontando hash SHA256
3. **Merge a Tre Vie**: Gestire inserimenti, aggiornamenti ed eliminazioni in singola esecuzione
4. **Idempotente**: Eseguire lo stesso pacchetto più volte produce lo stesso risultato
5. **Atomico**: Ogni sincronizzazione è una singola transazione
6. **Auditabile**: Logging completo di tutte le operazioni

## Architettura

### Flusso Alto Livello

```
┌─────────────────────────────────────────────────────────────────┐
│                      Sistema Sorgente                           │
│                   (ERP, Salesforce, MES)                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Passo 1: Estrazione & Hash │
              │   SELECT con HASHBYTES()     │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Passo 2: Split Condizionale│
              │   Instradamento basato su    │
              │   esistenza e confronto hash │
              └──────────────┬───────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌────────┐         ┌────────┐         ┌────────┐
    │ INSERT │         │ UPDATE │         │  SKIP  │
    │ Nuovo  │         │Modific │         │Nessun  │
    └────────┘         └────────┘         └────────┘
         │                   │                   │
         └───────────────────┴───────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Passo 3: Eliminazione Soft │
              │   Marca mancanti come elim.  │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Logging Audit              │
              │   Registra metriche & status │
              └──────────────────────────────┘
```

### Componenti Flusso Dati

```
Sorgente → Data Flow Task → Destinazione
           │
           ├─ OLE DB Source (Estrazione con Hash)
           ├─ Lookup Transformation (Verifica Esistenza)
           ├─ Conditional Split (Instradamento per Hash)
           ├─ OLE DB Command (Aggiornamento Modificati)
           ├─ OLE DB Destination (Inserimento Nuovi)
           └─ Execute SQL Task (Eliminazione Soft)
```

## Struttura Pacchetto SSIS

### Variabili Pacchetto

Ogni pacchetto SSIS definisce le seguenti variabili:

| Variabile | Tipo | Scopo | Esempio |
|----------|------|---------|---------|
| `SourceServer` | String | Server database sorgente | `ERP_PROD_SERVER` |
| `SourceDatabase` | String | Nome database sorgente | `ERP_Production` |
| `SourceSchema` | String | Nome schema sorgente | `dbo` |
| `SourceTable` | String | Nome tabella sorgente | `Customer` |
| `LandingSchema` | String | Nome schema landing | `ERP` |
| `LandingTable` | String | Nome tabella landing | `Customer` |
| `HashColumns` | String | Colonne da hashare | `CustomerName,VAT` |
| `PKColumns` | String | Colonne chiave primaria | `CompanyId,CustomerId` |
| `RecordsInserted` | Int32 | Conteggio record inseriti | 0 |
| `RecordsUpdated` | Int32 | Conteggio record aggiornati | 0 |
| `RecordsDeleted` | Int32 | Conteggio record eliminati | 0 |
| `ExecutionStart` | DateTime | Ora inizio pacchetto | `2026-05-21 10:00:00` |

### Connection Manager

1. **Source Connection**: Connessione OLE DB al sistema sorgente (sola lettura)
2. **Landing Connection**: Connessione OLE DB al database Landing (lettura-scrittura)
3. **Audit Connection**: Connessione OLE DB per logging (opzionale, può usare Landing)

### Flusso Controllo Pacchetto

```
┌─────────────────────────────────────────────────────────────┐
│  Flusso Controllo                                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. [Imposta Variabili] (Script Task)                      │
│     ↓                                                       │
│  2. [Truncate Staging] (Execute SQL Task)                  │
│     ↓                                                       │
│  3. [Estrai & Carica] (Data Flow Task) ──────┐             │
│     ↓                                         │             │
│  4. [Eliminazione Soft Mancanti] (Execute SQL Task)│       │
│     ↓                                         │             │
│  5. [Log Esecuzione] (Execute SQL Task)       │             │
│     ↓                                         │             │
│  6. [Pulizia Staging] (Execute SQL Task)      │             │
│                                               │             │
│  In Errore: [Log Errore] (Execute SQL Task) ←┘             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Passi di Sincronizzazione

### Passo 1: Estrazione dalla Sorgente con Calcolo Hash

**Scopo**: Leggere dati sorgente e calcolare hash per rilevamento cambiamenti

**Implementazione**: Componente OLE DB Source con query SQL dinamica

**Pattern Query SQL**:
```sql
-- Query dinamica generata da variabili pacchetto
SELECT 
    -- Colonne Chiave Primaria
    CompanyId,
    CustomerId,
    
    -- Hash Calcolato (ChangeHashKey)
    HASHBYTES('SHA2_256', 
        CONCAT(
            ISNULL(CustomerName, ''), '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey,
    
    -- Colonne Business
    CustomerName,
    VAT

FROM [ERP].[dbo].[Customer]
WHERE 1=1  -- Opzionale: aggiungere filtro incrementale per tabelle molto grandi
```

**Punti Chiave**:
- L'hash è calcolato alla sorgente per minimizzare trasferimento dati
- Usare `ISNULL()` per gestire valori NULL consistentemente
- Usare delimitatore (`|`) per evitare collisioni hash
- Convertire tutti i tipi di dati a stringa prima dell'hashing
- Includere solo colonne esistenti nella tabella Landing

**Considerazione Prestazioni**:
```sql
-- Per tabelle molto grandi (100M+ righe), aggiungere filtro
-- Esempio: caricamento incrementale basato su ModifiedDate
WHERE ModifiedDate >= DATEADD(DAY, -7, GETDATE())

-- Oppure usare change tracking se disponibile
WHERE CHANGE_TRACKING_VERSION >= @LastSyncVersion
```

### Passo 2: Split Condizionale e Instradamento

**Scopo**: Instradare record alle destinazioni appropriate basandosi su esistenza e rilevamento cambiamenti

**Implementazione**: Componenti Data Flow

#### 2.1 Lookup Transformation

**Configurazione**:
- **Tabella Lookup**: `Landing.ERP.Customer`
- **Colonne Join**: Colonne chiave primaria (`CompanyId`, `CustomerId`)
- **Colonne Restituite**: `ChangeHashKey`, `IsDeleted`
- **Output Nessuna Corrispondenza**: Nuovi record (instradamento a INSERT)
- **Output Corrispondenza**: Record esistenti (instradamento a Conditional Split)

**Modalità Cache**:
- **Full Cache**: Per dimensioni piccole (< 1M righe) - più veloce
- **Partial Cache**: Per tabelle medie (1M-10M righe) - bilanciato
- **No Cache**: Per tabelle molto grandi (> 10M righe) - efficiente in memoria

**Query Lookup**:
```sql
SELECT 
    CompanyId,
    CustomerId,
    ChangeHashKey,
    IsDeleted
FROM [Landing].[ERP].[Customer]
```

#### 2.2 Conditional Split Transformation

**Scopo**: Separare record abbinati in modificati vs non modificati

**Condizioni Split**:

| Nome Output | Condizione | Azione |
|-------------|-----------|--------|
| `Changed` | `Source.ChangeHashKey != Landing.ChangeHashKey` | Instrada a UPDATE |
| `Unchanged` | `Source.ChangeHashKey == Landing.ChangeHashKey` | Nessuna azione (ignora) |

**Sintassi Espressione** (SSIS):
```
-- Output Record Modificati
[Source_ChangeHashKey] != [Landing_ChangeHashKey]

-- Record Non Modificati (Output Predefinito)
-- Nessuna condizione necessaria - cattura tutti i record non modificati
```

#### 2.3 Instradamento Flusso Dati

**Tre Percorsi**:

1. **Output Nessuna Corrispondenza da Lookup** → OLE DB Destination (INSERT)
2. **Output Modificati da Conditional Split** → OLE DB Command (UPDATE)
3. **Output Non Modificati da Conditional Split** → Row Count (solo metriche, nessuna azione)

### Passo 2.4: INSERT Nuovi Record

**Componente**: OLE DB Destination

**Tabella Destinazione**: `[Landing].[ERP].[Customer]`

**Mappatura Colonne**:
```
Colonna Sorgente       → Colonna Destinazione
─────────────────────────────────────────────
CompanyId              → CompanyId
CustomerId             → CustomerId
ChangeHashKey          → ChangeHashKey
CustomerName           → CustomerName
VAT                    → VAT
CURRENT_TIMESTAMP      → InsertDatetime
CURRENT_TIMESTAMP      → UpdateDatetime
0 (costante)           → IsDeleted
```

**Derived Column Transformation** (prima di INSERT):
```
Nome Colonna      Espressione                     Tipo Dati
─────────────────────────────────────────────────────────────
InsertDatetime    GETDATE()                       DT_DBTIMESTAMP
UpdateDatetime    GETDATE()                       DT_DBTIMESTAMP
IsDeleted         (DT_BOOL)0                      DT_BOOL
```

**Query Insert** (generata dalla destinazione):
```sql
INSERT INTO [Landing].[ERP].[Customer]
(
    CompanyId,
    CustomerId,
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    CustomerName,
    VAT
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
```

### Passo 2.5: UPDATE Record Modificati

**Componente**: OLE DB Command

**Query Update**:
```sql
UPDATE [Landing].[ERP].[Customer]
SET 
    ChangeHashKey = ?,
    UpdateDatetime = CURRENT_TIMESTAMP,
    CustomerName = ?,
    VAT = ?
WHERE 
    CompanyId = ?
    AND CustomerId = ?
```

**Mappatura Parametri** (l'ordine conta):
```
Parametro  Colonna Sorgente   Tipo
────────────────────────────────────
Param_0    ChangeHashKey      BINARY(32)
Param_1    CustomerName       NVARCHAR(100)
Param_2    VAT                NVARCHAR(20)
Param_3    CompanyId          INT
Param_4    CustomerId         INT
```

**Note Importanti**:
- `InsertDatetime` NON è aggiornato (preserva tempo inserimento originale)
- `UpdateDatetime` è impostato a `CURRENT_TIMESTAMP`
- `IsDeleted` NON è modificato (preserva stato eliminazione se presente)
- TUTTE le colonne business sono aggiornate (anche se solo una è cambiata)

**Avviso Prestazioni**:
- OLE DB Command esegue UPDATE riga-per-riga (lento per grandi aggiornamenti)
- Per aggiornamenti bulk, considerare approccio staging table (vedi Ottimizzazione Prestazioni)

### Passo 3: Eliminazione Soft Record Mancanti

**Scopo**: Marcare record esistenti in Landing ma non nella sorgente come eliminati

**Implementazione**: Execute SQL Task

**Istruzione SQL**:
```sql
-- Eliminazione soft record non presenti in estrazione sorgente corrente
UPDATE t
SET 
    UpdateDatetime = CURRENT_TIMESTAMP,
    IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0  -- Processare solo record attivi
    AND NOT EXISTS (
        SELECT 1 
        FROM #Staging s  -- Tabella staging popolata durante data flow
        WHERE s.CompanyId = t.CompanyId 
            AND s.CustomerId = t.CustomerId
    );

-- Restituire conteggio per logging
SELECT @@ROWCOUNT AS DeletedCount;
```

**Approccio Alternativo** (senza staging):
```sql
-- Usare MERGE per tutte e tre le operazioni in una singola istruzione
MERGE [Landing].[ERP].[Customer] AS target
USING (
    -- Query sorgente da Passo 1
    SELECT 
        CompanyId,
        CustomerId,
        HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
        CustomerName,
        VAT
    FROM [ERP].[dbo].[Customer]
) AS source
ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- UPDATE record modificati
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- INSERT nuovi record
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        CompanyId, CustomerId, ChangeHashKey,
        InsertDatetime, UpdateDatetime, IsDeleted,
        CustomerName, VAT
    )
    VALUES (
        source.CompanyId, source.CustomerId, source.ChangeHashKey,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
        source.CustomerName, source.VAT
    )

-- ELIMINAZIONE SOFT record mancanti
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

## Pattern di Implementazione

### Pattern 1: Data Flow con Staging Table

**Pattern Più Comune** - Flessibile e performante per la maggior parte degli scenari

**Passi**:

1. **Crea/Trunca Staging Table**:
```sql
-- Execute SQL Task: Truncate Staging
IF OBJECT_ID('tempdb..#Staging_ERP_Customer') IS NOT NULL
    DROP TABLE #Staging_ERP_Customer;

CREATE TABLE #Staging_ERP_Customer
(
    CompanyId       INT,
    CustomerId      INT,
    ChangeHashKey   BINARY(32),
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20)
);
```

2. **Data Flow: Estrazione → Staging**:
   - OLE DB Source: Query con calcolo hash
   - OLE DB Destination: `#Staging_ERP_Customer`

3. **Execute SQL: Merge Staging → Landing**:
```sql
-- Esegui merge a tre vie
MERGE [Landing].[ERP].[Customer] AS target
USING #Staging_ERP_Customer AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

**Vantaggi**:
- Tutte le operazioni in singolo MERGE (atomico)
- Migliori prestazioni per aggiornamenti grandi
- Debug più semplice (tabella staging può essere ispezionata)
- Recupero errori più facile

**Svantaggi**:
- Richiede storage aggiuntivo (tabella staging)
- Processo a due passi (estrazione, poi merge)

### Pattern 2: Data Flow Diretto (Nessuno Staging)

**Più veloce per tabelle piccole** - Elimina staging intermedio

**Passi**:

1. **Data Flow con Instradamento Condizionale**:
   - OLE DB Source con calcolo hash
   - Lookup Transformation (abbinamento su PK)
   - Conditional Split (confronto hash)
   - OLE DB Destination (INSERT nuovi)
   - OLE DB Command (UPDATE modificati)

2. **Execute SQL: Eliminazione Soft**:
```sql
-- Marca come eliminati record non visti in questa esecuzione
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0
    AND t.UpdateDatetime < ?  -- Ora inizio pacchetto
    AND NOT EXISTS (
        SELECT 1 FROM [ERP].[dbo].[Customer] s
        WHERE s.CompanyId = t.CompanyId 
        AND s.CustomerId = t.CustomerId
    );
```

**Vantaggi**:
- Meno passi (più veloce per tabelle piccole)
- Nessuno storage staging richiesto
- Singolo passaggio attraverso i dati

**Svantaggi**:
- OLE DB Command è riga-per-riga (lento per aggiornamenti grandi)
- Debug più difficile (nessuno stato intermedio)
- Eliminazione soft richiede query separata alla sorgente

### Pattern 3: Ibrido (Staging + Flusso Ottimizzato)

**Migliori prestazioni per tabelle grandi** - Combina benefici di entrambi

**Passi**:

1. **Crea Staging con Indici**:
```sql
CREATE TABLE #Staging_ERP_Customer
(
    CompanyId       INT NOT NULL,
    CustomerId      INT NOT NULL,
    ChangeHashKey   BINARY(32) NOT NULL,
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20),
    
    PRIMARY KEY (CompanyId, CustomerId)
);

CREATE INDEX IX_Hash ON #Staging_ERP_Customer (ChangeHashKey);
```

2. **Bulk Insert a Staging**:
   - Fast Load abilitato
   - Logging minimale
   - Nessun vincolo durante insert

3. **T-SQL Merge** (come nel Pattern 1)

4. **Eliminazione Soft Indicizzata**:
```sql
-- Anti-join efficiente con staging indicizzato
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
    LEFT JOIN #Staging_ERP_Customer s
        ON t.CompanyId = s.CompanyId 
        AND t.CustomerId = s.CustomerId
WHERE t.IsDeleted = 0
    AND s.CompanyId IS NULL;
```

## Gestione Errori

### Gestione Transazioni

**Transazione Livello Pacchetto**:
```
Proprietà Pacchetto:
- TransactionOption: Required
- IsolationLevel: ReadCommitted
```

Tutti i task nel pacchetto partecipano a una singola transazione:
- Se qualsiasi task fallisce, l'intero pacchetto effettua rollback
- La tabella Landing rimane in stato consistente
- Si può ripetere in sicurezza l'intero pacchetto

**Gestione Errori Livello Task**:
```
Ogni Task:
- In Errore → Execute SQL Task (Log Errore)
- In Successo → Task Successivo
```

### Logging Errori

**Tabella Errori Audit**:
```sql
CREATE TABLE [audit].[ETLError]
(
    ErrorId             INT IDENTITY(1,1) PRIMARY KEY,
    PackageName         NVARCHAR(255) NOT NULL,
    TaskName            NVARCHAR(255) NULL,
    SourceSchema        NVARCHAR(50) NULL,
    SourceTable         NVARCHAR(100) NULL,
    ErrorCode           INT NULL,
    ErrorDescription    NVARCHAR(4000) NULL,
    ErrorDatetime       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Variabili Sistema SSIS
    ExecutionID         UNIQUEIDENTIFIER NULL,
    MachineName         NVARCHAR(128) NULL,
    UserName            NVARCHAR(128) NULL
);
```

**SQL Logging Errore** (Execute SQL Task in errore):
```sql
INSERT INTO [audit].[ETLError]
(
    PackageName,
    TaskName,
    SourceSchema,
    SourceTable,
    ErrorCode,
    ErrorDescription,
    ExecutionID,
    MachineName,
    UserName
)
VALUES
(
    ?,  -- @[System::PackageName]
    ?,  -- @[System::TaskName]
    ?,  -- @[User::SourceSchema]
    ?,  -- @[User::SourceTable]
    ?,  -- @[System::ErrorCode]
    ?,  -- @[System::ErrorDescription]
    ?,  -- @[System::ExecutionInstanceGUID]
    ?,  -- @[System::MachineName]
    ?,  -- @[System::UserName]
);
```

### Logica Retry

**Configurazione Pacchetto**:
- **Max Concurrent Executables**: 1 (previene esecuzioni concorrenti)
- **Checkpoint Enabled**: False (retry pacchetto completo, non a livello task)
- **Force Execution Result**: False (permetti completamento naturale)

**Configurazione SQL Agent Job**:
- **Tentativi Retry**: 3
- **Intervallo Retry**: 5 minuti
- **In Fallimento**: Notifica email

## Ottimizzazione Prestazioni

### Tecniche di Ottimizzazione

#### 1. Ottimizzazione Query Sorgente

**Hint Indici**:
```sql
-- Usare indice appropriato per scansione sorgente
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer] WITH (INDEX(IX_ModifiedDate))
WHERE ModifiedDate >= @LastSync
```

**Elaborazione Parallela**:
```sql
-- Abilitare esecuzione query parallela per tabelle grandi
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer]
OPTION (MAXDOP 4)
```

#### 2. Tuning Data Flow SSIS

**Configurazione Buffer**:
```
Proprietà Data Flow:
- DefaultBufferMaxRows: 10000 (predefinito)
- DefaultBufferSize: 10485760 (10MB predefinito)
- EngineThreads: 10 (o conteggio CPU)
```

**Impostazioni OLE DB Destination**:
```
Opzioni Fast Load:
- Table Lock: True
- Check Constraints: False
- Keep Identity: False
- Keep Nulls: True
- Rows per Batch: 100000
- Maximum Insert Commit Size: 100000
```

**Lookup Transformation**:
```
Impostazioni Cache (per Full Cache):
- Enable Memory Restriction: True
- Cache Size (MB): 256 (aggiustare in base a dimensione dimensione)
- Enable Disk Cache: True (per lookup grandi)
```

#### 3. Ottimizzazione Staging Table

**Usare Heap Table per Staging**:
```sql
-- Nessun indice clustered durante insert (più veloce)
CREATE TABLE #Staging_ERP_Customer
(
    CompanyId       INT NOT NULL,
    CustomerId      INT NOT NULL,
    ChangeHashKey   BINARY(32) NOT NULL,
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20)
);

-- Aggiungere indici DOPO insert
CREATE CLUSTERED INDEX CIX_PK 
    ON #Staging_ERP_Customer (CompanyId, CustomerId);

CREATE NONCLUSTERED INDEX IX_Hash 
    ON #Staging_ERP_Customer (ChangeHashKey);
```

#### 4. Minimizzare Locking

**Read Uncommitted per Sorgente**:
```sql
-- Le query sorgente non necessitano lock (sola lettura)
SELECT ...
FROM [ERP].[dbo].[Customer] WITH (NOLOCK)
WHERE ...
```

**Commit Batch per Landing**:
```sql
-- Commit ogni N righe per rilasciare lock
MERGE [Landing].[ERP].[Customer] AS target
USING #Staging AS source
    ON ...
WHEN MATCHED THEN UPDATE ...
WHEN NOT MATCHED THEN INSERT ...
OPTION (OPTIMIZE FOR (@BatchSize = 50000));
```

## Esempi

### Esempio 1: Caricamento Dimensione Semplice (Customer)

**Tabella Sorgente**:
```sql
-- [ERP].[dbo].[Customer]
CompanyId | CustomerId | CustomerName     | VAT      | CreditLimit
----------|------------|------------------|----------|------------
1         | 100        | Acme Corp        | IT12345  | 50000.00
1         | 101        | Beta LLC         | IT67890  | 25000.00
1         | 102        | Gamma Solutions  | IT11111  | 100000.00
```

**Tabella Landing**:
```sql
-- [Landing].[ERP].[Customer]
CREATE TABLE [Landing].[ERP].[Customer]
(
    CompanyId       INT NOT NULL,
    CustomerId      INT NOT NULL,
    ChangeHashKey   BINARY(32) NOT NULL,
    InsertDatetime  DATETIME NOT NULL,
    UpdateDatetime  DATETIME NOT NULL,
    IsDeleted       BIT NOT NULL,
    CustomerName    NVARCHAR(100) NOT NULL,
    VAT             NVARCHAR(20) NULL,
    PRIMARY KEY (CompanyId, CustomerId)
);
```

**Pacchetto SSIS: Load_ERP_Customer**

**Passo 1: Query Estrazione**:
```sql
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer]
```

**Risultato**:
```
CompanyId | CustomerId | ChangeHashKey  | CustomerName     | VAT
----------|------------|----------------|------------------|--------
1         | 100        | 0xA1B2C3...    | Acme Corp        | IT12345
1         | 101        | 0xD4E5F6...    | Beta LLC         | IT67890
1         | 102        | 0x789ABC...    | Gamma Solutions  | IT11111
```

**Passo 2: Data Flow**

Assumere che la tabella Landing attualmente abbia:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName  | VAT     | IsDeleted
----------|------------|---------------|---------------|---------|----------
1         | 100        | 0xA1B2C3...   | Acme Corp     | IT12345 | 0
1         | 101        | 0xOLDHASH..   | Beta LLC      | IT67890 | 0
1         | 103        | 0x999888...   | Delta Inc     | IT55555 | 0
```

**Risultati Lookup**:
- Customer 100: **Abbinato** (esiste in Landing)
- Customer 101: **Abbinato** (esiste in Landing)
- Customer 102: **Nessuna Corrispondenza** (nuovo record)
- Customer 103: (in Landing ma non in sorgente - sarà soft deleted)

**Conditional Split**:
- Customer 100: Hash corrisponde → **Non Modificato** (nessuna azione)
- Customer 101: Hash differisce → **Modificato** (instrada a UPDATE)
- Customer 102: Nessuna corrispondenza → **Nuovo** (instrada a INSERT)

**Azioni**:

1. **INSERT Customer 102**:
```sql
INSERT INTO [Landing].[ERP].[Customer]
VALUES (
    1, 102, 0x789ABC..., 
    '2026-05-21 10:15:00', '2026-05-21 10:15:00', 0,
    'Gamma Solutions', 'IT11111'
)
```

2. **UPDATE Customer 101**:
```sql
UPDATE [Landing].[ERP].[Customer]
SET 
    ChangeHashKey = 0xD4E5F6...,
    UpdateDatetime = '2026-05-21 10:15:00',
    CustomerName = 'Beta LLC',
    VAT = 'IT67890'
WHERE CompanyId = 1 AND CustomerId = 101
```

**Passo 3: Eliminazione Soft**:
```sql
UPDATE [Landing].[ERP].[Customer]
SET 
    UpdateDatetime = '2026-05-21 10:15:00',
    IsDeleted = 1
WHERE CompanyId = 1 AND CustomerId = 103
    AND IsDeleted = 0
```

**Stato Finale Tabella Landing**:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName     | VAT     | IsDeleted | UpdateDatetime
----------|------------|---------------|------------------|---------|-----------|----------------
1         | 100        | 0xA1B2C3...   | Acme Corp        | IT12345 | 0         | (invariato)
1         | 101        | 0xD4E5F6...   | Beta LLC         | IT67890 | 0         | 2026-05-21 10:15
1         | 102        | 0x789ABC...   | Gamma Solutions  | IT11111 | 0         | 2026-05-21 10:15
1         | 103        | 0x999888...   | Delta Inc        | IT55555 | 1         | 2026-05-21 10:15
```

**Metriche**:
- Record Inseriti: 1 (Customer 102)
- Record Aggiornati: 1 (Customer 101)
- Record Eliminati: 1 (Customer 103)
- Record Non Modificati: 1 (Customer 100)

## Migliori Pratiche

### 1. Progettazione Pacchetto

**Convenzione Nomenclatura**:
```
Pattern: Load_{Schema}_{Tabella}.dtsx
Esempi:
- Load_ERP_Customer.dtsx
- Load_SALESFORCE_Account.dtsx
- Load_MES_ProductionOrder.dtsx
```

**Parametrizzazione**:
```
Usare parametri pacchetto per:
- Stringa connessione sorgente
- Stringa connessione landing
- Criteri filtro (intervalli date)
- Dimensione batch

Evitare hardcoding:
- Nomi server
- Nomi database
- Credenziali
```

**Controllo Versione**:
- Memorizzare pacchetti in controllo sorgente (Git, TFS)
- Usare Project Deployment Model (SSISDB)
- Taggare release con numeri versione
- Documentare cambiamenti in annotazioni pacchetto

### 2. Calcolo Hash

**Ordinamento Consistente**:
```sql
-- Usare sempre stesso ordine colonne nell'hash
CONCAT(Col1, '|', Col2, '|', Col3)  -- Bene

-- Non cambiare ordine tra caricamenti
CONCAT(Col2, '|', Col1, '|', Col3)  -- Male (produce hash diverso)
```

**Gestione Tipo Dati**:
```sql
-- Convertire tutti i tipi a stringa con formato fisso
HASHBYTES('SHA2_256', 
    CONCAT(
        StringCol, '|',
        CAST(IntCol AS NVARCHAR(50)), '|',
        CAST(DecimalCol AS NVARCHAR(50)), '|',
        CONVERT(NVARCHAR(23), DateCol, 121),  -- Formato ISO YYYY-MM-DD HH:MI:SS.mmm
        ISNULL(NullableCol, '')
    )
)
```

**Escludere Colonne Volatili**:
```sql
-- Non includere nell'hash:
-- - Timestamp modifiche (causerebbe aggiornamenti continui)
-- - Colonne audit (CreatedBy, ModifiedBy)
-- - Valori calcolati che cambiano frequentemente
```

### 3. Monitoraggio e Logging

**Vista Esecuzione Audit**:
```sql
CREATE VIEW [audit].[vw_ETLExecutionSummary]
AS
SELECT
    PackageName,
    MAX(ExecutionDatetime) AS LastRun,
    SUM(RecordsInserted) AS TotalInserted,
    SUM(RecordsUpdated) AS TotalUpdated,
    SUM(RecordsDeleted) AS TotalDeleted,
    AVG(DATEDIFF(SECOND, ExecutionStart, ExecutionEnd)) AS AvgDurationSeconds
FROM [audit].[ETLLog]
GROUP BY PackageName;
```

**Alert Qualità Dati**:
```sql
-- Alert se troppi record sconosciuti/eliminati
IF (SELECT COUNT(*) FROM [Landing].[ERP].[Customer] WHERE IsDeleted = 1) > 1000
BEGIN
    RAISERROR('Numero anormalmente alto di eliminazioni rilevate', 16, 1);
END
```

### 4. Gestione Schema

**Cambiamenti Schema**:
```
1. Aggiungere colonna a tabella Landing
2. Aggiornare query estrazione (includere nuova colonna)
3. Aggiornare calcolo hash (includere nuova colonna)
4. Aggiornare mappature pacchetto SSIS
5. Testare con piccolo dataset
6. Deployare e monitorare
```

**Versionamento Hash**:
```sql
-- Includere versione nel hash per cambiamenti schema
HASHBYTES('SHA2_256', 
    CONCAT(
        'v2|',  -- Prefisso versione
        Col1, '|',
        Col2, '|',
        ColNuova  -- Nuova colonna
    )
)
```

## Monitoraggio e Logging

### Tabella Log ETL

```sql
CREATE TABLE [audit].[ETLLog]
(
    ETLLogId            INT IDENTITY(1,1) PRIMARY KEY,
    PackageName         NVARCHAR(255) NOT NULL,
    SourceSchema        NVARCHAR(50) NOT NULL,
    SourceTable         NVARCHAR(100) NOT NULL,
    RecordsInserted     INT NOT NULL DEFAULT 0,
    RecordsUpdated      INT NOT NULL DEFAULT 0,
    RecordsDeleted      INT NOT NULL DEFAULT 0,
    RecordsUnchanged    INT NOT NULL DEFAULT 0,
    ExecutionStart      DATETIME NOT NULL,
    ExecutionEnd        DATETIME NULL,
    ExecutionStatus     NVARCHAR(20) NOT NULL,  -- Success, Failed, Running
    ErrorMessage        NVARCHAR(4000) NULL,
    
    -- Metriche Performance
    SourceRowCount      INT NULL,
    LandingRowCount     INT NULL,
    DurationSeconds     AS DATEDIFF(SECOND, ExecutionStart, ExecutionEnd),
    
    -- Metadati SSIS
    ExecutionID         UNIQUEIDENTIFIER NULL,
    ServerName          NVARCHAR(128) NULL,
    UserName            NVARCHAR(128) NULL
);

-- Indice per query comuni
CREATE INDEX IX_PackageExecution 
    ON [audit].[ETLLog] (PackageName, ExecutionStart DESC);
```

### Dashboard Monitoraggio

**Vista Stato Corrente**:
```sql
CREATE VIEW [audit].[vw_CurrentLoadStatus]
AS
SELECT
    s.name AS SourceSchema,
    t.name AS SourceTable,
    l.LastLoadTime,
    DATEDIFF(MINUTE, l.LastLoadTime, GETDATE()) AS MinutesSinceLoad,
    l.LastStatus,
    l.RecordsLoaded,
    
    -- Indicatore salute
    CASE
        WHEN DATEDIFF(HOUR, l.LastLoadTime, GETDATE()) > 24 
            THEN 'STALE'
        WHEN l.LastStatus = 'Failed' 
            THEN 'ERROR'
        WHEN DATEDIFF(HOUR, l.LastLoadTime, GETDATE()) > 6 
            THEN 'WARNING'
        ELSE 'OK'
    END AS HealthStatus
FROM sys.schemas s
CROSS JOIN sys.tables t
LEFT JOIN (
    SELECT 
        SourceSchema,
        SourceTable,
        MAX(ExecutionEnd) AS LastLoadTime,
        MAX(ExecutionStatus) AS LastStatus,
        SUM(RecordsInserted + RecordsUpdated) AS RecordsLoaded
    FROM [audit].[ETLLog]
    WHERE ExecutionStatus = 'Success'
    GROUP BY SourceSchema, SourceTable
) l ON s.name = l.SourceSchema AND t.name = l.SourceTable
WHERE s.name NOT IN ('sys', 'audit', 'dbo');
```

---

## Riepilogo

Questo pattern di sincronizzazione fornisce:

✅ **Consistenza**: Replica fedele dei dati sorgente nella Landing zone  
✅ **Efficienza**: Rilevamento cambiamenti basato su hash minimizza overhead  
✅ **Affidabilità**: Pattern idempotente permette retry sicuri  
✅ **Tracciabilità**: Logging completo di tutte le operazioni  
✅ **Manutenibilità**: Struttura pacchetto consistente tra tutte le tabelle  
✅ **Prestazioni**: Ottimizzazioni per tabelle di tutte le dimensioni  

Seguendo questi pattern, crei un processo ETL robusto che carica efficientemente i dati dai sistemi sorgente mantenendo integrità dei dati e traccia di audit completa.

---

**Versione Documento**: 1.0  
**Ultimo Aggiornamento**: 21 maggio 2026  
**Stack Tecnologico**: Microsoft SQL Server 2016+, SSIS 2016+, BIML 5.0+
