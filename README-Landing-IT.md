# Data Warehouse Landing Zone - Pattern di Progettazione

## Indice
- [Panoramica](#panoramica)
- [Architettura](#architettura)
- [Concetti Chiave](#concetti-chiave)
- [Progettazione dello Schema](#progettazione-dello-schema)
- [Struttura delle Tabelle](#struttura-delle-tabelle)
- [Pattern di Aggiornamento](#pattern-di-aggiornamento)
- [Vantaggi e Motivazioni](#vantaggi-e-motivazioni)
- [Esempi](#esempi)
- [Best Practice](#best-practice)

## Panoramica

La **Landing Zone** (nota anche come **Area di Staging** o **Livello Dati Grezzi**) è il primo livello in un'architettura di data warehouse dove i dati provenienti da vari sistemi sorgente vengono inizialmente caricati. Questo documento descrive un pattern collaudato per progettare e gestire la Landing zone utilizzando Microsoft SQL Server.

### Scopo della Landing Zone

La Landing zone svolge diverse funzioni critiche:
- **Disaccoppiamento**: Isola il data warehouse dai sistemi sorgente, riducendo le dipendenze e il carico sui database operazionali
- **Archiviazione Temporale**: Fornisce uno snapshot dei dati sorgente in specifici punti nel tempo
- **Rilevamento delle Modifiche**: Traccia quali dati sono cambiati dall'ultimo caricamento
- **Qualità dei Dati**: Agisce come punto di controllo prima che i dati si spostino a livelli più raffinati
- **Auditabilità**: Mantiene un registro di quando i dati sono arrivati e come sono cambiati

## Architettura

### Struttura del Database

```
Database Landing
├── audit (schema)
│   ├── Tables (tabelle di log per operazioni ETL)
│   ├── Views (viste di monitoraggio e reporting)
│   └── Stored Procedures (procedure di logging e utilità)
├── ERP (schema)
│   ├── Customer
│   ├── Order
│   └── ... (altre tabelle ERP)
├── SALESFORCE (schema)
│   ├── Account
│   ├── Opportunity
│   └── ... (altri oggetti Salesforce)
├── MES (schema)
│   ├── ProductionOrder
│   ├── WorkCenter
│   └── ... (altre tabelle MES)
└── ... (schemi sorgente aggiuntivi)
```

### Principi di Progettazione

1. **Database Landing Unico**: Tutti i sistemi sorgente inseriscono i loro dati in un database comune
2. **Schema-per-Sorgente**: Ogni sorgente dati ha il proprio schema, denominato in MAIUSCOLO
3. **Isolamento degli Schema**: Gli schemi sorgente sono logicamente separati per sicurezza e organizzazione
4. **Schema di Audit**: Schema di audit comune per monitoraggio e logging cross-sorgente

## Concetti Chiave

### Change Data Capture (CDC)

I meccanismi CDC tradizionali tracciano le modifiche a livello di database sorgente. Questo pattern implementa un approccio **CDC basato su hash** che:
- Funziona con qualsiasi sistema sorgente (non richiede funzionalità CDC a livello di database)
- Rileva le modifiche confrontando valori hash invece che confronti colonna-per-colonna
- Fornisce rilevamento efficiente delle modifiche con overhead computazionale minimo

### Rilevamento delle Modifiche Basato su Hash

La colonna **ChangeHashKey** contiene un hash SHA256 di tutte le colonne business rilevanti. Questa tecnica:
- **Efficienza**: Confronto singolo invece di confronti multipli di colonne
- **Consistenza**: Deterministico - gli stessi dati producono sempre lo stesso hash
- **Sensibilità**: Qualsiasi modifica nei dati sorgente produce un hash diverso
- **Prestazioni**: La colonna hash indicizzata abilita ricerche veloci

**Formula**:
```
ChangeHashKey = SHA256(Colonna1 + Colonna2 + ... + ColonnaN)
```

### Pattern di Eliminazione Soft

Invece di rimuovere fisicamente i record, il flag **IsDeleted** marca i record come eliminati. Questo approccio:
- **Preserva la Storia**: I record eliminati rimangono nel database per scopi di audit
- **Abilita il Recupero**: I dati eliminati accidentalmente possono essere ripristinati
- **Supporta Query Temporali**: L'analisi può includere o escludere i record eliminati
- **Mantiene il Contesto Referenziale**: I record correlati possono ancora riferirsi a entità eliminate

### Idempotenza

Il pattern di aggiornamento è **idempotente**, il che significa:
- Eseguire lo stesso caricamento più volte produce lo stesso risultato
- I caricamenti falliti possono essere ritentati in sicurezza senza corruzione dei dati
- Non vengono creati record duplicati
- Supporta sia strategie di caricamento complete che incrementali

### Tracciamento Temporale

Ogni record traccia il suo ciclo di vita attraverso colonne timestamp:
- **InsertDatetime**: Quando il record è apparso per la prima volta nella Landing zone
- **UpdateDatetime**: Quando il record è stato modificato l'ultima volta
- Abilita analisi point-in-time e metriche del tasso di modifica

## Progettazione dello Schema

### Convenzioni di Nomenclatura

| Elemento | Convenzione | Esempio |
|---------|-----------|---------|
| Database | PascalCase | `Landing` |
| Schema Sorgente | MAIUSCOLO | `ERP`, `SALESFORCE`, `MES` |
| Schema Audit | minuscolo | `audit` |
| Nome Tabella | Corrisponde alla tabella sorgente | `Customer`, `Order` |
| Colonne Chiave Business | Corrisponde alla sorgente | `CompanyId`, `CustomerId` |
| Colonne Tecniche | PascalCase | `ChangeHashKey`, `InsertDatetime` |

### Pattern Schema-per-Sorgente

Ogni sistema sorgente ottiene il proprio schema per diverse ragioni:

**Vantaggi**:
- **Sicurezza**: Concedere permessi a livello di schema (es. il team ERP accede solo allo schema `ERP`)
- **Organizzazione**: Chiara separazione delle responsabilità
- **Evitamento delle Collisioni**: Sorgenti diverse possono avere tabelle con lo stesso nome (es. `ERP.Order` vs `SALESFORCE.Order`)
- **Elaborazione Selettiva**: Elaborare o ricaricare sorgenti specifiche indipendentemente
- **Documentazione**: Il nome dello schema identifica immediatamente la provenienza dei dati

**Esempio**:
```sql
-- Tabella Customer ERP
ERP.Customer

-- Tabella Account Salesforce (equivalente a Customer in ERP)
SALESFORCE.Account
```

## Struttura delle Tabelle

### Layout Standard delle Colonne

Ogni tabella Landing segue questa struttura:

```sql
CREATE TABLE [SCHEMA_SORGENTE].[NomeTabella]
(
    -- Colonne Chiave Business (dalla sorgente)
    [ChiavePrimaria1]  [TipoDati]      NOT NULL,
    [ChiavePrimaria2]  [TipoDati]      NOT NULL,
    
    -- Rilevamento Modifiche & Metadati
    [ChangeHashKey]    BINARY(32)      NOT NULL,
    [InsertDatetime]   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    [UpdateDatetime]   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    [IsDeleted]        BIT             NOT NULL DEFAULT 0,
    
    -- Colonne Business (dalla sorgente)
    [Colonna1]         [TipoDati]      [NULL/NOT NULL],
    [Colonna2]         [TipoDati]      [NULL/NOT NULL],
    ...
    
    -- Vincolo Chiave Primaria
    CONSTRAINT [PK_SORGENTE_NomeTabella] PRIMARY KEY CLUSTERED 
    (
        [ChiavePrimaria1],
        [ChiavePrimaria2]
    )
);

-- Indice su ChangeHashKey per prestazioni
CREATE NONCLUSTERED INDEX [IX_SORGENTE_NomeTabella_ChangeHashKey] 
    ON [SCHEMA_SORGENTE].[NomeTabella] ([ChangeHashKey]);

-- Indice su colonne temporali per query di audit
CREATE NONCLUSTERED INDEX [IX_SORGENTE_NomeTabella_Temporal] 
    ON [SCHEMA_SORGENTE].[NomeTabella] ([UpdateDatetime], [IsDeleted]);
```

### Descrizioni delle Colonne

| Colonna | Tipo | Scopo | Popolato |
|--------|------|---------|-----------|
| Chiave/i Business | Varia | Identificatore univoco dalla sorgente | Ogni caricamento |
| ChangeHashKey | BINARY(32) | Hash SHA256 delle colonne business | Ogni caricamento (calcolato) |
| InsertDatetime | DATETIME | Timestamp primo inserimento | Solo inserimento |
| UpdateDatetime | DATETIME | Timestamp ultima modifica | Inserimento & aggiornamento |
| IsDeleted | BIT | Flag eliminazione soft | Inserimento (0) & eliminazione (1) |
| Colonne Business | Varia | Colonne dati sorgente | Ogni caricamento |

### Strategia di Selezione delle Colonne

**Colonne Chiave Business**: Includere tutte le colonne che formano la chiave primaria della tabella sorgente
- Queste identificano univocamente ogni record
- Utilizzate per abbinare dati sorgente a dati landing

**Colonne Business**: Includere solo le colonne necessarie per l'elaborazione downstream
- Non tutte le colonne sorgente devono essere nel data warehouse
- Selezionare colonne rilevanti per business intelligence e reporting
- Escludere dati sensibili se non necessari (minimizza requisiti di conformità)
- Escludere colonne binarie grandi (immagini, documenti) a meno che non siano specificamente richieste

**Calcolo ChangeHashKey**: Hashare solo le colonne business
- NON includere le colonne chiave business (non cambiano)
- NON includere le colonne tecniche (InsertDatetime, UpdateDatetime, IsDeleted)
- Includere TUTTE le colonne su cui vuoi rilevare modifiche

## Pattern di Aggiornamento

### I Quattro Scenari

La logica di aggiornamento segue un **pattern simile a MERGE** che gestisce quattro scenari distinti:

```
┌─────────────────────────────────────────────────────────────┐
│                Estrazione Tabella Sorgente                  │
│         (Chiavi Primarie + Colonne Business)                │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ├─ Calcola ChangeHashKey
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│          Abbina con Tabella Landing su PK                   │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │Scenario │    │Scenario │    │Scenario │
    │    A    │    │  B & C  │    │    D    │
    └─────────┘    └─────────┘    └─────────┘
```

#### Scenario A: Nuovo Record
**Condizione**: Il record esiste nella sorgente ma NON in landing

**Azione**: INSERT nuovo record
```sql
INSERT INTO [Landing].[SCHEMA].[Tabella]
(
    [ChiavePrimaria1],
    [ChiavePrimaria2],
    [ChangeHashKey],
    [InsertDatetime],
    [UpdateDatetime],
    [IsDeleted],
    [Colonna1],
    [Colonna2]
)
VALUES
(
    @ChiavePrimaria1,
    @ChiavePrimaria2,
    @HashCalcolato,           -- Hash SHA256
    CURRENT_TIMESTAMP,        -- Imposta ora inserimento
    CURRENT_TIMESTAMP,        -- Imposta ora aggiornamento
    0,                        -- Non eliminato
    @Colonna1,
    @Colonna2
);
```

**Esempio**: Un nuovo cliente viene creato nel sistema ERP
- Prima volta che questo cliente appare nel data warehouse
- Tutti i campi sono popolati dalla sorgente
- InsertDatetime e UpdateDatetime impostati all'ora corrente

#### Scenario B: Nessuna Modifica
**Condizione**: Il record esiste sia in sorgente che in landing, ChangeHashKey corrisponde

**Azione**: NESSUNA AZIONE (salta il record)
```sql
-- Pseudocodice
IF sorgente.ChangeHashKey = landing.ChangeHashKey THEN
    SKIP; -- Nessuna modifica rilevata
END IF;
```

**Esempio**: I dati del cliente non sono cambiati dall'ultimo caricamento
- Il confronto hash è molto veloce (confronto di un singolo valore)
- Minimizza aggiornamenti non necessari
- Preserva UpdateDatetime per riflettere il tempo di modifica effettivo

#### Scenario C: Record Modificato
**Condizione**: Il record esiste sia in sorgente che in landing, ChangeHashKey differisce

**Azione**: UPDATE record esistente
```sql
UPDATE [Landing].[SCHEMA].[Tabella]
SET
    [ChangeHashKey] = @NuovoHashCalcolato,  -- Aggiorna hash
    [UpdateDatetime] = CURRENT_TIMESTAMP,   -- Aggiorna timestamp
    [Colonna1] = @NuovaColonna1,            -- Aggiorna colonne business
    [Colonna2] = @NuovaColonna2
WHERE
    [ChiavePrimaria1] = @ChiavePrimaria1
    AND [ChiavePrimaria2] = @ChiavePrimaria2;
```

**Esempio**: Il nome o la partita IVA del cliente è cambiata nell'ERP
- L'hash rileva automaticamente la modifica
- Tutte le colonne business vengono aggiornate (anche se solo una è cambiata)
- UpdateDatetime riflette quando la modifica è stata rilevata
- InsertDatetime rimane invariato (tempo di arrivo originale preservato)

#### Scenario D: Record Eliminato
**Condizione**: Il record esiste in landing (IsDeleted = 0) ma NON nella sorgente

**Azione**: ELIMINAZIONE SOFT (marca come eliminato)
```sql
UPDATE [Landing].[SCHEMA].[Tabella]
SET
    [UpdateDatetime] = CURRENT_TIMESTAMP,   -- Aggiorna timestamp
    [IsDeleted] = 1                         -- Marca come eliminato
WHERE
    [ChiavePrimaria1] = @ChiavePrimaria1
    AND [ChiavePrimaria2] = @ChiavePrimaria2
    AND [IsDeleted] = 0;                    -- Solo aggiorna se non già eliminato
```

**Esempio**: Record cliente rimosso dall'ERP
- Il record rimane nella tabella Landing per scopi di audit
- Il flag IsDeleted previene l'elaborazione nei livelli downstream
- UpdateDatetime riflette quando l'eliminazione è stata rilevata
- Può essere interrogato per analisi storiche

**Nota**: I record con `IsDeleted = 1` NON vengono ri-eliminati se ancora mancanti nei caricamenti successivi

### Approcci di Implementazione

#### Opzione 1: Istruzione MERGE (Consigliata)
```sql
MERGE [Landing].[ERP].[Customer] AS target
USING #DatiSorgente AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Scenario C: Aggiorna quando hash cambiato
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- Scenario A: Inserisci nuovi record
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

-- Scenario D: Eliminazione soft record mancanti
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

#### Opzione 2: Istruzioni Separate
```sql
-- Scenario A: Inserisci nuovi record
INSERT INTO [Landing].[ERP].[Customer] (...)
SELECT ...
FROM #DatiSorgente s
WHERE NOT EXISTS (
    SELECT 1 FROM [Landing].[ERP].[Customer] t
    WHERE t.CompanyId = s.CompanyId AND t.CustomerId = s.CustomerId
);

-- Scenario C: Aggiorna record modificati
UPDATE t
SET ...
FROM [Landing].[ERP].[Customer] t
INNER JOIN #DatiSorgente s 
    ON t.CompanyId = s.CompanyId AND t.CustomerId = s.CustomerId
WHERE t.ChangeHashKey <> s.ChangeHashKey;

-- Scenario D: Eliminazione soft record mancanti
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0
    AND NOT EXISTS (
        SELECT 1 FROM #DatiSorgente s
        WHERE s.CompanyId = t.CompanyId AND s.CustomerId = t.CustomerId
    );
```

## Vantaggi e Motivazioni

### Perché il Rilevamento delle Modifiche Basato su Hash?

**Approccio Tradizionale** (confronto colonna-per-colonna):
```sql
WHERE target.Colonna1 <> source.Colonna1
   OR target.Colonna2 <> source.Colonna2
   OR target.Colonna3 <> source.Colonna3
   ...
```
**Problemi**:
- Clausola WHERE complessa per tabelle con molte colonne
- La gestione dei NULL richiede logica speciale (ISNULL o COALESCE)
- Le prestazioni degradano con più colonne
- Difficile da mantenere man mano che lo schema evolve

**Approccio Basato su Hash**:
```sql
WHERE target.ChangeHashKey <> source.ChangeHashKey
```
**Vantaggi**:
- ✅ Confronto singolo indipendentemente dal numero di colonne
- ✅ Deterministico e consistente
- ✅ Gestione NULL incorporata nel calcolo dell'hash
- ✅ Può essere indicizzato per le prestazioni
- ✅ Facile da mantenere e comprendere

### Perché le Eliminazioni Soft?

**Eliminazione Hard** (rimozione fisica):
```sql
DELETE FROM [Landing].[ERP].[Customer]
WHERE ...
```
**Problemi**:
- Dati storici persi per sempre
- Traccia di audit interrotta
- Impossibile distinguere "mai esistito" da "è stato eliminato"
- Impossibile tracciare quando si è verificata l'eliminazione

**Eliminazione Soft** (flag IsDeleted):
```sql
UPDATE [Landing].[ERP].[Customer]
SET IsDeleted = 1
WHERE ...
```
**Vantaggi**:
- ✅ Traccia di audit completa mantenuta
- ✅ Possibilità di ripristinare dati eliminati accidentalmente
- ✅ I processi downstream possono scegliere di includere/escludere record eliminati
- ✅ L'analisi temporale rimane accurata
- ✅ Conformità normativa (GDPR, SOX, ecc.) più facile

### Perché Schema-per-Sorgente?

**Approccio Schema Singolo**:
```
Landing.dbo.ERP_Customer
Landing.dbo.ERP_Order
Landing.dbo.Salesforce_Account
Landing.dbo.Salesforce_Opportunity
```
**Problemi**:
- Le collisioni dei nomi delle tabelle richiedono prefissi
- La sicurezza deve essere gestita a livello di tabella
- Difficile concedere accesso a "tutte le tabelle ERP"
- Inquinamento del namespace

**Approccio Schema-per-Sorgente**:
```
Landing.ERP.Customer
Landing.ERP.Order
Landing.SALESFORCE.Account
Landing.SALESFORCE.Opportunity
```
**Vantaggi**:
- ✅ Separazione naturale del namespace
- ✅ Grant di sicurezza a livello di schema
- ✅ Chiara tracciabilità dei dati
- ✅ Più facile ricaricare un'intera sorgente
- ✅ I nomi delle tabelle corrispondono esattamente al sistema sorgente

### Perché le Colonne Temporali?

**InsertDatetime** abilita:
- Identificare quando i record sono entrati per la prima volta nel data warehouse
- Misurare la latenza dei dati (tempo dalla creazione nella sorgente all'arrivo)
- Debug dei processi ETL
- Requisiti di conformità e audit

**UpdateDatetime** abilita:
- Analisi della frequenza di modifica
- Identificazione di dati obsoleti
- Risoluzione dei problemi di qualità dei dati
- Monitoraggio SLA (quanto sono freschi i dati?)
- Elaborazione incrementale nei livelli downstream

## Esempi

### Esempio 1: Tabella Customer ERP

**Tabella Sorgente** (database ERP):
```sql
-- dbo.Customer nel database ERP
CREATE TABLE dbo.Customer
(
    CompanyId       INT             NOT NULL,
    CustomerId      INT             NOT NULL,
    CustomerName    NVARCHAR(100)   NOT NULL,
    VAT             NVARCHAR(20)    NULL,
    Address         NVARCHAR(200)   NULL,
    CreditLimit     DECIMAL(18,2)   NULL,
    PRIMARY KEY (CompanyId, CustomerId)
);
```

**Tabella Landing** (database Landing):
```sql
-- ERP.Customer nel database Landing
CREATE TABLE [Landing].[ERP].[Customer]
(
    -- Chiavi Business
    CompanyId           INT             NOT NULL,
    CustomerId          INT             NOT NULL,
    
    -- Colonne Tecniche
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdateDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Colonne Business (selezionate dalla sorgente)
    CustomerName        NVARCHAR(100)   NOT NULL,
    VAT                 NVARCHAR(20)    NULL,
    
    CONSTRAINT PK_ERP_Customer PRIMARY KEY CLUSTERED (CompanyId, CustomerId)
);

CREATE NONCLUSTERED INDEX IX_ERP_Customer_ChangeHashKey 
    ON [Landing].[ERP].[Customer] (ChangeHashKey);
```

**Calcolo Hash** (pseudocodice):
```
ChangeHashKey = SHA256(CustomerName + '|' + ISNULL(VAT, ''))
```

**Nota**: Address e CreditLimit NON sono inclusi (non necessari nel DW)

### Esempio 2: Processo ETL Completo

**Passo 1**: Estrazione dalla sorgente
```sql
-- Estrai dati dall'ERP
SELECT 
    CompanyId,
    CustomerId,
    CustomerName,
    VAT,
    -- Calcola hash
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey
INTO #DatiSorgente
FROM [Server_ERP].[ERP].[dbo].[Customer];
```

**Passo 2**: Applica logica MERGE
```sql
MERGE [Landing].[ERP].[Customer] AS target
USING #DatiSorgente AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Aggiorna record modificati (Scenario C)
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- Inserisci nuovi record (Scenario A)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

-- Eliminazione soft record mancanti (Scenario D)
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

**Passo 3**: Log risultati (nello schema audit)
```sql
INSERT INTO [Landing].[audit].[ETLLog]
(
    SourceSchema,
    SourceTable,
    RecordsInserted,
    RecordsUpdated,
    RecordsDeleted,
    ExecutionDatetime
)
VALUES
(
    'ERP',
    'Customer',
    @ConteggiInseriti,
    @ConteggiAggiornati,
    @ConteggiEliminati,
    CURRENT_TIMESTAMP
);
```

### Esempio 3: Walkthrough degli Scenari

**Stato Iniziale** (tabella Landing):
```
CompanyId | CustomerId | ChangeHashKey | CustomerName  | VAT        | IsDeleted
----------|------------|---------------|---------------|------------|----------
1         | 100        | 0xABCD...     | Acme Corp     | IT12345    | 0
1         | 101        | 0xEF01...     | Beta LLC      | IT67890    | 0
```

**Dati Sorgente** (ERP corrente):
```
CompanyId | CustomerId | CustomerName      | VAT        
----------|------------|-------------------|------------
1         | 100        | Acme Corp         | IT12345    
1         | 101        | Beta Industries   | IT67890    
1         | 102        | Gamma Solutions   | IT11111    
```

**Elaborazione**:

1. **Cliente 100**: Hash corrisponde → Scenario B (nessuna azione)
   - Nessuna modifica rilevata
   - Record non toccato

2. **Cliente 101**: Hash differisce → Scenario C (aggiornamento)
   - CustomerName cambiato da "Beta LLC" a "Beta Industries"
   - Nuovo hash calcolato
   - UpdateDatetime aggiornato
   - Colonne business aggiornate

3. **Cliente 102**: Non in landing → Scenario A (inserimento)
   - Nuovo cliente creato nell'ERP
   - Nuovo record inserito
   - InsertDatetime e UpdateDatetime impostati

**Risultato**:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName      | VAT     | IsDeleted | UpdateDatetime
----------|------------|---------------|-------------------|---------|-----------|----------------
1         | 100        | 0xABCD...     | Acme Corp         | IT12345 | 0         | (invariato)
1         | 101        | 0x1234...     | Beta Industries   | IT67890 | 0         | 2026-05-20 10:30
1         | 102        | 0x5678...     | Gamma Solutions   | IT11111 | 0         | 2026-05-20 10:30
```

## Best Practice

### 1. Calcolo Hash

**Delimitatori Consistenti**:
```sql
-- Bene: Usa delimitatore per evitare ambiguità di concatenazione
HASHBYTES('SHA2_256', CONCAT(Col1, '|', Col2, '|', Col3))

-- Male: Valori "AB" + "CD" produce stesso risultato di "ABC" + "D"
HASHBYTES('SHA2_256', CONCAT(Col1, Col2, Col3))
```

**Gestione NULL**:
```sql
-- Bene: Gestione esplicita dei NULL
HASHBYTES('SHA2_256', 
    CONCAT(
        Col1, '|',
        ISNULL(Col2, ''), '|',
        ISNULL(Col3, '')
    )
)

-- Male: La propagazione NULL rende l'intero hash NULL
HASHBYTES('SHA2_256', CONCAT(Col1, '|', Col2, '|', Col3))
```

**Consistenza dei Tipi di Dati**:
```sql
-- Bene: Converti in stringa in modo consistente
HASHBYTES('SHA2_256', 
    CONCAT(
        StringCol, '|',
        CAST(NumericCol AS NVARCHAR(50)), '|',
        CONVERT(NVARCHAR(23), DateCol, 121)  -- Formato ISO
    )
)
```

### 2. Ottimizzazione delle Prestazioni

**Strategia di Indicizzazione**:
```sql
-- Chiave primaria per operazioni MERGE
CREATE PRIMARY KEY (ChiaveBusiness1, ChiaveBusiness2);

-- Indice hash per rilevamento modifiche
CREATE INDEX IX_ChangeHash ON Tabella (ChangeHashKey);

-- Indice temporale per query di audit
CREATE INDEX IX_Temporal ON Tabella (UpdateDatetime, IsDeleted) 
    INCLUDE (ChiaveBusiness1, ChiaveBusiness2);

-- Indice composito per elaborazione downstream
CREATE INDEX IX_Active ON Tabella (IsDeleted) 
    WHERE IsDeleted = 0;  -- Indice filtrato per record attivi
```

**Usa Tabelle Temporanee**:
```sql
-- Estrai prima in tabella temporanea
SELECT ... INTO #DatiSorgente FROM [LinkedServer].[Database].[Schema].[Tabella];

-- Crea indici sulla tabella temporanea
CREATE INDEX IX_Temp ON #DatiSorgente (ChiavePrimaria1, ChiavePrimaria2);

-- Poi MERGE
MERGE [Landing].[Schema].[Tabella] AS target
USING #DatiSorgente AS source ...
```

### 3. Gestione Errori

**Gestione Transazioni**:
```sql
BEGIN TRY
    BEGIN TRANSACTION;
    
    -- Estrazione
    SELECT ... INTO #DatiSorgente FROM ...;
    
    -- Trasformazione (calcola hash)
    UPDATE #DatiSorgente SET ChangeHashKey = HASHBYTES(...);
    
    -- Caricamento (MERGE)
    MERGE [Landing].[Schema].[Tabella] ...;
    
    -- Audit
    INSERT INTO [audit].[ETLLog] ...;
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    -- Log errore
    INSERT INTO [audit].[ETLError] (
        SourceSchema, SourceTable, ErrorMessage, ErrorDatetime
    )
    VALUES (
        'ERP', 'Customer', ERROR_MESSAGE(), CURRENT_TIMESTAMP
    );
    
    THROW;
END CATCH;
```

### 4. Progettazione Schema Audit

**Tabella Log ETL**:
```sql
CREATE TABLE [audit].[ETLLog]
(
    ETLLogId            INT             IDENTITY(1,1) PRIMARY KEY,
    SourceSchema        NVARCHAR(50)    NOT NULL,
    SourceTable         NVARCHAR(100)   NOT NULL,
    RecordsInserted     INT             NOT NULL DEFAULT 0,
    RecordsUpdated      INT             NOT NULL DEFAULT 0,
    RecordsDeleted      INT             NOT NULL DEFAULT 0,
    ExecutionDatetime   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ExecutionDuration   INT             NULL,  -- millisecondi
    RowsProcessed       INT             NULL
);
```

**Vista di Monitoraggio**:
```sql
CREATE VIEW [audit].[vw_DataFreshness]
AS
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    MAX(UpdateDatetime) AS LastUpdate,
    DATEDIFF(MINUTE, MAX(UpdateDatetime), CURRENT_TIMESTAMP) AS MinutesSinceUpdate,
    COUNT(*) AS TotalRecords,
    SUM(CASE WHEN IsDeleted = 0 THEN 1 ELSE 0 END) AS ActiveRecords,
    SUM(CASE WHEN IsDeleted = 1 THEN 1 ELSE 0 END) AS DeletedRecords
FROM sys.schemas s
INNER JOIN sys.tables t ON s.schema_id = t.schema_id
CROSS APPLY (
    SELECT UpdateDatetime, IsDeleted
    FROM [Landing].[schema].[table]  -- SQL dinamico necessario in pratica
) x
WHERE s.name NOT IN ('audit', 'dbo', 'sys')
GROUP BY s.name, t.name;
```

### 5. Controlli di Qualità dei Dati

**Validazione Post-Caricamento**:
```sql
-- Verifica chiavi esterne orfane
SELECT 'Ordini Orfani' AS Problema, COUNT(*) AS Conteggio
FROM [Landing].[ERP].[Order] o
WHERE NOT EXISTS (
    SELECT 1 FROM [Landing].[ERP].[Customer] c
    WHERE c.CompanyId = o.CompanyId 
    AND c.CustomerId = o.CustomerId
    AND c.IsDeleted = 0
);

-- Verifica valori NULL inattesi
SELECT 'Nomi Cliente NULL' AS Problema, COUNT(*) AS Conteggio
FROM [Landing].[ERP].[Customer]
WHERE CustomerName IS NULL
AND IsDeleted = 0;

-- Verifica chiavi business duplicate (non dovrebbe mai accadere)
SELECT 'Clienti Duplicati' AS Problema, COUNT(*) AS Conteggio
FROM (
    SELECT CompanyId, CustomerId, COUNT(*) AS Cnt
    FROM [Landing].[ERP].[Customer]
    GROUP BY CompanyId, CustomerId
    HAVING COUNT(*) > 1
) x;
```

### 6. Caricamento Incrementale vs Completo

**Caricamento Completo** (consigliato per Landing):
- Carica tutti i dati sorgente ogni volta
- Logica semplice
- Idempotente (sicuro rieseguire)
- Rileva automaticamente le eliminazioni (Scenario D)
- Consigliato per il livello Landing

**Caricamento Incrementale** (usa con cautela):
- Carica solo record modificati (basato su timestamp sorgente)
- Logica più complessa
- Più veloce per tabelle molto grandi
- Il rilevamento delle eliminazioni richiede logica separata
- Considera per livelli downstream, non Landing

**Esempio - Caricamento Completo con ottimizzazione TRUNCATE**:
```sql
-- Per piccole tabelle dimensionali, truncate e reload può essere più veloce di MERGE
BEGIN TRANSACTION;

    TRUNCATE TABLE [Landing].[ERP].[CustomerCategory];
    
    INSERT INTO [Landing].[ERP].[CustomerCategory] (...)
    SELECT ... FROM [Server_ERP].[ERP].[dbo].[CustomerCategory];

COMMIT TRANSACTION;
```

### 7. Evoluzione dello Schema

Quando lo schema sorgente cambia:

**Aggiunta Colonne**:
```sql
-- 1. Aggiungi colonna alla tabella Landing
ALTER TABLE [Landing].[ERP].[Customer]
ADD EmailAddress NVARCHAR(100) NULL;

-- 2. Aggiorna calcolo hash per includere nuova colonna
-- (aggiorna procedura ETL)

-- 3. Il prossimo caricamento rileverà TUTTI i record come modificati
-- (l'hash cambia perché il calcolo include la nuova colonna)
-- Questo è il comportamento atteso e corretto
```

**Rimozione Colonne**:
```sql
-- 1. Aggiorna calcolo hash (rimuovi colonna)
-- 2. Il prossimo caricamento rileverà TUTTI i record come modificati
-- 3. Successivamente: elimina colonna dalla tabella Landing (opzionale)
ALTER TABLE [Landing].[ERP].[Customer]
DROP COLUMN VecchiaColonna;
```

**Best Practice**: Versiona il tuo calcolo hash
```sql
-- Opzione 1: Aggiungi colonna versione hash
ALTER TABLE [Landing].[ERP].[Customer]
ADD HashVersion TINYINT NOT NULL DEFAULT 1;

-- Opzione 2: Includi versione nell'hash
ChangeHashKey = HASHBYTES('SHA2_256', CONCAT('v2|', Col1, '|', Col2, ...))
```

---

## Riepilogo

Questo pattern di progettazione della Landing zone fornisce:

✅ **Scalabilità**: Gestisce più sistemi sorgente indipendentemente  
✅ **Prestazioni**: Il rilevamento delle modifiche basato su hash è veloce ed efficiente  
✅ **Auditabilità**: Tracciamento temporale completo ed eliminazioni soft  
✅ **Affidabilità**: I caricamenti idempotenti possono essere ritentati in sicurezza  
✅ **Manutenibilità**: Struttura chiara e pattern consistenti  
✅ **Flessibilità**: Funziona con qualsiasi sistema sorgente (nessun requisito CDC)  

Seguendo questi principi, crei una base robusta per il tuo data warehouse che disaccoppia i sistemi sorgente, traccia le modifiche in modo efficiente e mantiene tracce di audit complete per conformità e analisi.

---

**Versione Documento**: 1.0  
**Ultimo Aggiornamento**: 20 maggio 2026  
**Stack Tecnologico**: Microsoft SQL Server 2016+
