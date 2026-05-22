# Data Warehouse - Pattern di Progettazione

## Indice
- [Panoramica](#panoramica)
- [Architettura](#architettura)
- [Concetti Chiave](#concetti-chiave)
- [Progettazione Schema](#progettazione-schema)
- [Tabelle Dimensionali](#tabelle-dimensionali)
- [Tabelle dei Fatti](#tabelle-dei-fatti)
- [Tabelle Bridge](#tabelle-bridge)
- [Viste Applicative](#viste-applicative)
- [Pattern di Sincronizzazione](#pattern-di-sincronizzazione)
- [Benefici e Giustificazione](#benefici-e-giustificazione)
- [Esempi](#esempi)
- [Migliori Pratiche](#migliori-pratiche)

## Panoramica

Il layer **Data Warehouse** è il nucleo analitico della piattaforma dati dove i dati grezzi provenienti dalla Landing zone vengono trasformati in un modello dimensionale ottimizzato per business intelligence e reporting. Questo documento descrive un pattern consolidato per progettare e gestire un data warehouse utilizzando Microsoft SQL Server e la modellazione dimensionale in stile Kimball.

### Scopo del Data Warehouse

Il layer Data Warehouse svolge diverse funzioni critiche:
- **Modellazione Dimensionale**: Organizza i dati in fatti e dimensioni per interrogazioni intuitive
- **Integrazione Dati**: Combina dati da più sistemi sorgente in entità di business unificate
- **Normalizzazione**: Standardizza nomi di colonne, tipi di dati e regole di business tra le sorgenti
- **Prestazioni**: Ottimizza le strutture dati per query analitiche e reporting
- **Logica di Business**: Implementa misure calcolate, gerarchie e regole di business
- **Controllo Accessi**: Fornisce viste sicure e specifiche dei dati analitici per le applicazioni

## Architettura

### Struttura del Database

```
Database DataWarehouse
├── Staging (schema)
│   ├── CustomerStaging (calcoli intermedi)
│   ├── OrderEnrichment (trasformazioni parziali)
│   └── ... (altre tabelle staging)
├── Dim (schema)
│   ├── Customer (tabella dimensionale)
│   ├── CustomerView (vista sorgente per sincronizzazione)
│   ├── Product (tabella dimensionale)
│   ├── ProductView (vista sorgente per sincronizzazione)
│   └── ... (altre dimensioni)
├── Fact (schema)
│   ├── Sales (tabella dei fatti)
│   ├── SalesView (vista sorgente per sincronizzazione)
│   ├── Production (tabella dei fatti)
│   ├── ProductionView (vista sorgente per sincronizzazione)
│   └── ... (altri fatti)
├── Bridge (schema)
│   ├── ProductCategory (bridge molti-a-molti)
│   ├── CustomerGroup (bridge molti-a-molti)
│   └── ... (altri bridge)
├── vERP (schema - viste applicative)
│   ├── ProductionOrders (vista per consumo ERP)
│   ├── Customers (vista per consumo ERP)
│   └── ... (altre viste ERP)
├── vPowerBI (schema - viste applicative)
│   ├── SalesAnalysis (vista per Power BI)
│   └── ... (altre viste BI)
└── ... (schemi applicativi aggiuntivi)
```

### Flusso Dati

```
┌─────────────────────────────────────────────────────────────┐
│                    Database Landing                         │
│         (schemi ERP, SALESFORCE, MES)                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Schema Staging                            │
│        (Calcoli e trasformazioni intermedie)                │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌──────────────────┐           ┌──────────────────┐
│  Schema Dim      │           │  Schema Fact     │
│  (Dimensioni)    │◄──────────┤  (Fatti)         │
└────────┬─────────┘           └────────┬─────────┘
         │                              │
         └───────────┬──────────────────┘
                     │
                     ▼
         ┌────────────────────────┐
         │   Schema Bridge        │
         │  (Molti-a-Molti)       │
         └────────┬───────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│          Viste Applicative (vERP, vPowerBI)                 │
│     (Viste sicure e curate per consumatori specifici)       │
└─────────────────────────────────────────────────────────────┘
```

### Principi di Progettazione

1. **Modellazione Dimensionale Kimball**: Schema a stella con fatti e dimensioni
2. **Separazione delle Responsabilità**: Staging, dimensioni, fatti, bridge e viste applicative in schemi separati
3. **Sincronizzazione Basata su Viste**: Le viste sorgente definiscono la logica di trasformazione; le tabelle memorizzano i risultati materializzati
4. **Chiavi Surrogate**: Chiavi intere generate da sequence per tutte le dimensioni
5. **Membri Speciali**: Gestione standard di chiavi esterne NULL e sconosciute
6. **Integrità Referenziale**: Applicazione rigorosa tramite membri speciali e logica di sincronizzazione

## Concetti Chiave

### Modellazione Dimensionale Kimball

La **metodologia Kimball** è un approccio bottom-up alla progettazione di data warehouse che si concentra su:
- **Schema a Stella**: Tabelle dei fatti al centro circondate da tabelle dimensionali
- **Focus sui Processi di Business**: Modellare i processi di business (es. Vendite, Produzione) come fatti
- **Dimensioni Conformate**: Dimensioni condivise tra più tabelle dei fatti
- **Dichiarazione della Granularità**: Definizione esplicita della granularità delle tabelle dei fatti

**Benefici**:
- Intuitivo per gli utenti di business
- Ottimizzato per prestazioni delle query
- Flessibile per analisi ad-hoc
- Approccio di sviluppo incrementale

### Tabelle Fatti vs Dimensioni

**Tabelle Dimensionali** (CHI, COSA, DOVE, QUANDO, PERCHÉ):
- Attributi descrittivi sulle entità di business
- Esempi: Customer, Product, Date, Location
- Relativamente piccole (migliaia a milioni di righe)
- Tabelle larghe (molte colonne)
- Cambiano lentamente nel tempo

**Tabelle dei Fatti** (METRICHE, MISURE):
- Misure numeriche di eventi di business
- Esempi: Transazioni di vendita, Ordini di produzione, Click web
- Molto grandi (milioni a miliardi di righe)
- Tabelle strette (chiavi esterne + misure)
- Solo in aggiunta o snapshot periodici

### Chiavi Surrogate

Una **chiave surrogata** è un identificatore artificiale che non ha significato di business:
```sql
CustomerKey INT  -- Chiave surrogata (sequence generata)
vs
CustomerId INT   -- Chiave naturale/di business (dal sistema sorgente)
```

**Perché Usare Chiavi Surrogate?**
- **Indipendenza**: Disaccoppia il warehouse dai cambiamenti del sistema sorgente
- **Integrazione**: Combina dati da più sorgenti con chiavi diverse
- **Prestazioni**: Le chiavi intere sono più veloci delle chiavi composite o stringa
- **Storico**: Abilita il tracciamento dei cambiamenti dimensionali (SCD Tipo 2)
- **Semplicità**: Chiavi esterne a singola colonna nelle tabelle dei fatti

**Generazione**: 
```sql
-- Usando SEQUENCE di SQL Server
CREATE SEQUENCE Dim.CustomerSequence START WITH 1 INCREMENT BY 1;
CustomerKey = NEXT VALUE FOR Dim.CustomerSequence
```

### Membri Speciali (Vuoto e Sconosciuto)

Ogni dimensione contiene **due record speciali**:

**Membro Vuoto (Chiave = -1)**:
- Rappresenta chiavi esterne NULL nelle tabelle dei fatti
- Usato quando la dimensione non è applicabile
- Esempio: OrderKey = -1 quando Customer non ha ordini

**Membro Sconosciuto (Chiave = -101)**:
- Rappresenta chiavi esterne non abbinate nelle tabelle dei fatti
- Usato quando la chiave di business esiste ma il record dimensionale è mancante o eliminato
- Esempio: CustomerKey = -101 quando OrderCustomerId = 999 ma Customer 999 non esiste o IsDeleted = 1

**Benefici**:
- **Preserva i Dati**: I record dei fatti si caricano anche con riferimenti dimensionali mancanti
- **Integrità Referenziale**: Nessuna chiave esterna NULL; tutti i fatti riferiscono dimensioni valide
- **Auditing**: Può identificare problemi di qualità dei dati (conteggio di membri Sconosciuti)
- **Semplicità Query**: Non è necessario outer join o gestione NULL nei report

### Dimensioni a Cambio Lento (SCD)

Questo pattern implementa **SCD Tipo 1** (sovrascrittura):
- Solo valore corrente (nessun tracciamento storico)
- Gli aggiornamenti dimensionali sovrascrivono i valori esistenti
- Semplice ed efficiente
- Adatto quando i valori dimensionali storici non sono necessari

**Approcci alternativi** (non implementati in questo pattern):
- **SCD Tipo 2**: Tracciare lo storico completo con date di validità e flag corrente
- **SCD Tipo 3**: Tracciare storico limitato (es. valore corrente e precedente)

### Sincronizzazione Basata su Viste

Il pattern di sincronizzazione usa **viste come sorgenti** e **tabelle come destinazioni**:

```
Tabelle Landing → Vista Dimensione → Tabella Dimensione
```

**Vista Dimensione**: 
- Definisce la logica di trasformazione (join, calcoli, normalizzazione)
- Agisce come "stato desiderato" della dimensione

**Tabella Dimensione**: 
- Snapshot materializzato della vista
- Ottimizzata con indici per prestazioni query
- Aggiornata tramite stesso pattern MERGE della Landing

**Benefici**:
- Chiara separazione tra logica (vista) e storage (tabella)
- Le viste possono essere testate indipendentemente
- Le tabelle forniscono prestazioni consistenti
- Stesso pattern di sincronizzazione in tutto il warehouse

### Pattern LEFT JOIN per i Fatti

Le viste dei fatti usano **LEFT JOIN** alle dimensioni per garantire che tutti i fatti si carichino:

```sql
SELECT
    f.*,
    COALESCE(d.CustomerKey, -101) AS CustomerKey  -- Sconosciuto se nessuna corrispondenza
FROM Landing.ERP.Order f
LEFT JOIN Dim.Customer d 
    ON f.CustomerId = d.CustomerId
    AND d.IsDeleted = 0
```

**Logica**:
- **Inner join abbinato**: Usare la chiave surrogata della dimensione
- **Chiave esterna NULL**: Usare -1 (membro vuoto)
- **Nessuna corrispondenza o eliminato**: Usare -101 (membro sconosciuto)

## Progettazione Schema

### Convenzioni di Nomenclatura

| Elemento | Convenzione | Esempio |
|---------|-----------|---------|
| Database | PascalCase | `DataWarehouse` |
| Schema | PascalCase | `Dim`, `Fact`, `Bridge`, `Staging` |
| Schema Applicativo | Prefisso minuscolo + PascalCase | `vERP`, `vPowerBI` |
| Tabella Dimensione | Nome singolare | `Customer`, `Product` |
| Vista Dimensione | Nome tabella + "View" | `CustomerView`, `ProductView` |
| Tabella Fatti | Plurale o nome processo | `Sales`, `ProductionOrders` |
| Vista Fatti | Nome tabella + "View" | `SalesView`, `ProductionOrdersView` |
| Chiave Surrogata | Nome dimensione + "Key" | `CustomerKey`, `ProductKey` |
| Chiave Naturale | Coincide con sorgente | `CustomerId`, `ProductId` |
| Sequence | Schema + Tabella + "Sequence" | `DimCustomerSequence` |

### Organizzazione Schema

**Schema Staging**:
- Scopo: Trasformazioni intermedie, calcoli complessi
- Visibilità: Solo interna ai processi ETL
- Ciclo di vita: Le tabelle possono essere troncate/ricreate frequentemente
- Esempi: Join complessi, aggregazioni, applicazione regole di business

**Schema Dim**:
- Scopo: Tabelle dimensionali e loro viste sorgente
- Visibilità: Consumate da viste dei fatti e viste applicative
- Ciclo di vita: Persistente, sincronizzato con cambiamenti Landing

**Schema Fact**:
- Scopo: Tabelle dei fatti e loro viste sorgente
- Visibilità: Consumate da viste applicative
- Ciclo di vita: Solo in aggiunta o snapshot periodici

**Schema Bridge**:
- Scopo: Relazioni molti-a-molti tra fatti e dimensioni
- Visibilità: Consumate da viste applicative
- Ciclo di vita: Sincronizzato con cambiamenti dimensionali

**Schemi Applicativi (vERP, vPowerBI, ecc.)**:
- Scopo: Viste curate per applicazioni o gruppi di utenti specifici
- Visibilità: Esterna al data warehouse (consumate da applicazioni)
- Ciclo di vita: Interfacce stabili (versionate se cambiamenti breaking)

## Tabelle Dimensionali

### Struttura

Ogni dimensione segue questo pattern:

**Vista Dimensione** (definisce la trasformazione):
```sql
CREATE VIEW Dim.CustomerView
AS
SELECT
    -- Chiave Surrogata (sarà generata durante la sincronizzazione)
    -- NEXT VALUE FOR Dim.CustomerSequence AS CustomerKey
    
    -- Chiavi Naturali (dalla sorgente)
    c.CompanyId,
    c.CustomerId,
    
    -- Colonne Tecniche (dalla Landing)
    c.ChangeHashKey,
    c.InsertDatetime,
    c.UpdateDatetime,
    c.IsDeleted,
    
    -- Attributi di Business (normalizzati)
    c.CustomerName AS Name,
    c.VAT AS TaxIdentifier,
    ct.CategoryName AS Category,
    cr.RegionName AS Region,
    
    -- Attributi Calcolati
    CASE 
        WHEN c.CreditLimit > 100000 THEN 'Alto Valore'
        WHEN c.CreditLimit > 10000 THEN 'Medio Valore'
        ELSE 'Standard'
    END AS CustomerSegment
    
FROM [Landing].[ERP].[Customer] c
LEFT JOIN [Landing].[ERP].[CustomerCategory] ct 
    ON c.CategoryId = ct.CategoryId
LEFT JOIN [Staging].[CustomerRegion] cr 
    ON c.RegionId = cr.RegionId
WHERE c.IsDeleted = 0  -- Solo record attivi
```

**Tabella Dimensione** (storage materializzato):
```sql
CREATE TABLE Dim.Customer
(
    -- Chiave Surrogata
    CustomerKey         INT             NOT NULL,
    
    -- Chiavi Naturali
    CompanyId           INT             NOT NULL,
    CustomerId          INT             NOT NULL,
    
    -- Colonne Tecniche
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL,
    UpdateDatetime      DATETIME        NOT NULL,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Attributi di Business
    Name                NVARCHAR(100)   NOT NULL,
    TaxIdentifier       NVARCHAR(20)    NULL,
    Category            NVARCHAR(50)    NULL,
    Region              NVARCHAR(50)    NULL,
    CustomerSegment     NVARCHAR(20)    NULL,
    
    -- Chiave Primaria sulla Surrogata
    CONSTRAINT PK_Dim_Customer PRIMARY KEY CLUSTERED (CustomerKey),
    
    -- Vincolo unico sulla Chiave Naturale
    CONSTRAINT UQ_Dim_Customer_NaturalKey UNIQUE (CompanyId, CustomerId)
);

-- Indice per sincronizzazione (lookup chiave naturale)
CREATE NONCLUSTERED INDEX IX_Dim_Customer_NaturalKey 
    ON Dim.Customer (CompanyId, CustomerId);

-- Indice per rilevamento cambiamenti
CREATE NONCLUSTERED INDEX IX_Dim_Customer_ChangeHash 
    ON Dim.Customer (ChangeHashKey);
```

**Sequence** (generazione chiave surrogata):
```sql
CREATE SEQUENCE Dim.CustomerSequence 
    START WITH 1 
    INCREMENT BY 1;
```

### Inizializzazione Membri Speciali

Ogni dimensione deve essere inizializzata con membri speciali:

```sql
-- Inizializzare sequence oltre le chiavi membri speciali
ALTER SEQUENCE Dim.CustomerSequence RESTART WITH 1;

-- Inserire Membro Vuoto (Chiave = -1)
INSERT INTO Dim.Customer
(
    CustomerKey,
    CompanyId,
    CustomerId,
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    Name,
    TaxIdentifier,
    Category,
    Region,
    CustomerSegment
)
VALUES
(
    -1,                                  -- Chiave membro vuoto
    -1,
    -1,
    0x00,                                -- Hash vuoto
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0,                                   -- Mai eliminato
    '(Vuoto)',
    NULL,
    '(Vuoto)',
    '(Vuoto)',
    '(Vuoto)'
);

-- Inserire Membro Sconosciuto (Chiave = -101)
INSERT INTO Dim.Customer
(
    CustomerKey,
    CompanyId,
    CustomerId,
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    Name,
    TaxIdentifier,
    Category,
    Region,
    CustomerSegment
)
VALUES
(
    -101,                                -- Chiave membro sconosciuto
    -101,
    -101,
    0x00,                                -- Hash vuoto
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0,                                   -- Mai eliminato
    '(Sconosciuto)',
    NULL,
    '(Sconosciuto)',
    '(Sconosciuto)',
    '(Sconosciuto)'
);
```

### Tipi di Colonne Dimensionali

**Chiave Surrogata (CustomerKey)**:
- Generata da sequence
- Non cambia mai
- Chiave primaria della tabella dimensione
- Chiave esterna nelle tabelle dei fatti

**Chiavi Naturali (CompanyId, CustomerId)**:
- Identificatori di business dal sistema sorgente
- Usati per lookup durante la sincronizzazione
- Vincolo unico applicato

**Colonne Tecniche (ChangeHashKey, InsertDatetime, UpdateDatetime, IsDeleted)**:
- Ereditate dal layer Landing
- Stesso scopo e utilizzo
- Abilitano rilevamento cambiamenti e audit

**Attributi di Business (Name, Category, Region, ecc.)**:
- Colonne descrittive per analisi
- Nomi normalizzati (es. CustomerName → Name)
- Possono combinare dati da più sorgenti
- Possono includere valori calcolati/derivati

## Tabelle dei Fatti

### Struttura

Ogni tabella dei fatti segue questo pattern:

**Vista Fatti** (definisce la trasformazione):
```sql
CREATE VIEW Fact.SalesView
AS
SELECT
    -- Chiavi Naturali (dalla sorgente)
    o.CompanyId,
    o.OrderId,
    o.LineNumber,
    
    -- Colonne Tecniche (dalla Landing)
    o.ChangeHashKey,
    o.InsertDatetime,
    o.UpdateDatetime,
    o.IsDeleted,
    
    -- Chiavi Esterne Dimensionali (chiavi surrogate via LEFT JOIN)
    COALESCE(dc.CustomerKey, 
        CASE WHEN o.CustomerId IS NULL THEN -1 ELSE -101 END) AS CustomerKey,
    COALESCE(dp.ProductKey, 
        CASE WHEN o.ProductId IS NULL THEN -1 ELSE -101 END) AS ProductKey,
    COALESCE(dd.DateKey, -101) AS OrderDateKey,
    COALESCE(de.EmployeeKey, 
        CASE WHEN o.SalesPersonId IS NULL THEN -1 ELSE -101 END) AS SalesPersonKey,
    
    -- Dimensioni Degeneri (attributi alta cardinalità memorizzati nel fatto)
    o.OrderNumber,
    o.InvoiceNumber,
    
    -- Misure (fatti numerici)
    o.Quantity,
    o.UnitPrice,
    o.DiscountPercent,
    o.LineTotal,
    o.TaxAmount,
    
    -- Misure Calcolate
    o.LineTotal - o.TaxAmount AS NetAmount,
    o.Quantity * o.UnitPrice - o.LineTotal AS DiscountAmount
    
FROM [Landing].[ERP].[OrderDetail] o
INNER JOIN [Landing].[ERP].[Order] oh 
    ON o.CompanyId = oh.CompanyId 
    AND o.OrderId = oh.OrderId
LEFT JOIN Dim.Customer dc 
    ON o.CompanyId = dc.CompanyId 
    AND o.CustomerId = dc.CustomerId
    AND dc.IsDeleted = 0
LEFT JOIN Dim.Product dp 
    ON o.ProductId = dp.ProductId
    AND dp.IsDeleted = 0
LEFT JOIN Dim.Date dd 
    ON CAST(oh.OrderDate AS DATE) = dd.DateValue
LEFT JOIN Dim.Employee de 
    ON o.SalesPersonId = de.EmployeeId
    AND de.IsDeleted = 0
WHERE o.IsDeleted = 0;
```

**Tabella Fatti** (storage materializzato):
```sql
CREATE TABLE Fact.Sales
(
    -- Chiavi Naturali (definizione granularità)
    CompanyId           INT             NOT NULL,
    OrderId             INT             NOT NULL,
    LineNumber          INT             NOT NULL,
    
    -- Colonne Tecniche
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL,
    UpdateDatetime      DATETIME        NOT NULL,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Chiavi Esterne Dimensionali (chiavi surrogate)
    CustomerKey         INT             NOT NULL,
    ProductKey          INT             NOT NULL,
    OrderDateKey        INT             NOT NULL,
    SalesPersonKey      INT             NOT NULL,
    
    -- Dimensioni Degeneri
    OrderNumber         NVARCHAR(50)    NOT NULL,
    InvoiceNumber       NVARCHAR(50)    NULL,
    
    -- Misure
    Quantity            DECIMAL(18,2)   NOT NULL,
    UnitPrice           DECIMAL(18,2)   NOT NULL,
    DiscountPercent     DECIMAL(5,2)    NOT NULL,
    LineTotal           DECIMAL(18,2)   NOT NULL,
    TaxAmount           DECIMAL(18,2)   NOT NULL,
    NetAmount           DECIMAL(18,2)   NOT NULL,
    DiscountAmount      DECIMAL(18,2)   NOT NULL,
    
    -- Chiave Primaria (granularità naturale)
    CONSTRAINT PK_Fact_Sales PRIMARY KEY CLUSTERED 
        (CompanyId, OrderId, LineNumber),
    
    -- Chiavi Esterne alle Dimensioni
    CONSTRAINT FK_Fact_Sales_Customer 
        FOREIGN KEY (CustomerKey) REFERENCES Dim.Customer (CustomerKey),
    CONSTRAINT FK_Fact_Sales_Product 
        FOREIGN KEY (ProductKey) REFERENCES Dim.Product (ProductKey),
    CONSTRAINT FK_Fact_Sales_Date 
        FOREIGN KEY (OrderDateKey) REFERENCES Dim.Date (DateKey),
    CONSTRAINT FK_Fact_Sales_Employee 
        FOREIGN KEY (SalesPersonKey) REFERENCES Dim.Employee (EmployeeKey)
);

-- Indici per pattern di query comuni
CREATE NONCLUSTERED INDEX IX_Fact_Sales_Customer 
    ON Fact.Sales (CustomerKey) INCLUDE (LineTotal, Quantity);

CREATE NONCLUSTERED INDEX IX_Fact_Sales_Product 
    ON Fact.Sales (ProductKey) INCLUDE (LineTotal, Quantity);

CREATE NONCLUSTERED INDEX IX_Fact_Sales_Date 
    ON Fact.Sales (OrderDateKey) INCLUDE (LineTotal, Quantity);
```

### Tipi di Colonne dei Fatti

**Chiavi Naturali (CompanyId, OrderId, LineNumber)**:
- Definiscono la granularità (livello di dettaglio) del fatto
- Chiave primaria della tabella dei fatti
- Usate per sincronizzazione e deduplicazione

**Chiavi Esterne Dimensionali (CustomerKey, ProductKey, ecc.)**:
- Chiavi surrogate dalle tabelle dimensionali
- Sempre popolate (mai NULL) usando membri speciali
- Abilitano join schema a stella

**Dimensioni Degeneri (OrderNumber, InvoiceNumber)**:
- Identificatori di transazione ad alta cardinalità
- Non giustificano una tabella dimensionale separata
- Memorizzate direttamente nella tabella dei fatti

**Misure (Quantity, UnitPrice, LineTotal, ecc.)**:
- Valori numerici da aggregare
- Supportano operazioni SUM, AVG, MIN, MAX, COUNT
- Possono essere memorizzate (dalla sorgente) o calcolate (derivate)

**Misure Additive vs Non-Additive**:
- **Additive**: Possono essere sommate su tutte le dimensioni (es. Quantity, LineTotal)
- **Semi-Additive**: Possono essere sommate su alcune dimensioni (es. Saldo Conto - non nel tempo)
- **Non-Additive**: Non possono essere sommate (es. Prezzo Unitario, Rapporti) - usare AVG o misure calcolate

## Tabelle Bridge

### Scopo

Le tabelle bridge risolvono **relazioni molti-a-molti** tra fatti e dimensioni:

**Scenari**:
- Product appartiene a più Categories
- Customer appartiene a più Groups
- Employee riporta a più Managers (organizzazione a matrice)
- Transaction taggata con più Hashtags

### Struttura

```sql
-- Tabella Bridge
CREATE TABLE Bridge.ProductCategory
(
    ProductKey          INT             NOT NULL,
    CategoryKey         INT             NOT NULL,
    
    -- Ponderazione opzionale per allocazione
    AllocationPercent   DECIMAL(5,2)    NULL,
    
    -- Colonne Tecniche
    InsertDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdateDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Chiave Primaria
    CONSTRAINT PK_Bridge_ProductCategory 
        PRIMARY KEY CLUSTERED (ProductKey, CategoryKey),
    
    -- Chiavi Esterne
    CONSTRAINT FK_Bridge_ProductCategory_Product 
        FOREIGN KEY (ProductKey) REFERENCES Dim.Product (ProductKey),
    CONSTRAINT FK_Bridge_ProductCategory_Category 
        FOREIGN KEY (CategoryKey) REFERENCES Dim.Category (CategoryKey)
);

-- Indici per query in entrambe le direzioni
CREATE NONCLUSTERED INDEX IX_Bridge_ProductCategory_Category 
    ON Bridge.ProductCategory (CategoryKey, ProductKey);
```

### Utilizzo nelle Query

```sql
-- Trovare tutti i prodotti in una categoria (direzione uno-a-molti)
SELECT 
    c.CategoryName,
    p.ProductName,
    f.LineTotal
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category c ON b.CategoryKey = c.CategoryKey
INNER JOIN Dim.Product p ON f.ProductKey = p.ProductKey
WHERE c.CategoryName = 'Elettronica';

-- Allocare vendite su più categorie (molti-a-molti con ponderazione)
SELECT 
    c.CategoryName,
    SUM(f.LineTotal * b.AllocationPercent / 100) AS AllocatedSales
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category c ON b.CategoryKey = c.CategoryKey
GROUP BY c.CategoryName;
```

## Viste Applicative

### Scopo

Gli schemi specifici per applicazioni forniscono **viste curate e sicure** per consumo esterno:

**Benefici**:
- **Sicurezza**: Ogni applicazione ha il proprio utente con permessi ristretti
- **Semplificazione**: Join e logica complessi nascosti ai consumatori
- **Astrazione**: I cambiamenti di schema non rompono le dipendenze esterne
- **Versionamento**: Può mantenere più versioni di viste durante le migrazioni
- **Prestazioni**: Può includere viste indicizzate o risultati materializzati

### Struttura

**Schema Applicativo** (es. vERP):
```sql
-- Creare schema per applicazione ERP
CREATE SCHEMA vERP;

-- Creare utente dedicato
CREATE USER dw_erp WITH PASSWORD = 'PasswordSicura123!';

-- Concedere accesso read-only solo allo schema vERP
GRANT SELECT ON SCHEMA::vERP TO dw_erp;
DENY SELECT ON SCHEMA::Dim TO dw_erp;
DENY SELECT ON SCHEMA::Fact TO dw_erp;
DENY SELECT ON SCHEMA::Staging TO dw_erp;
```

**Vista Applicativa**:
```sql
CREATE VIEW vERP.ProductionOrders
AS
SELECT
    -- Chiavi di Business
    po.CompanyId,
    po.ProductionOrderId,
    
    -- Dimensioni (nomi business-friendly)
    p.ProductCode,
    p.ProductName,
    w.WorkCenterCode,
    w.WorkCenterName,
    e.EmployeeName AS Operator,
    d.DateValue AS ProductionDate,
    
    -- Misure
    po.PlannedQuantity,
    po.ActualQuantity,
    po.ScrapQuantity,
    po.ActualQuantity - po.ScrapQuantity AS GoodQuantity,
    
    -- Metriche Calcolate
    CASE 
        WHEN po.PlannedQuantity > 0 
        THEN (po.ActualQuantity * 100.0 / po.PlannedQuantity)
        ELSE 0 
    END AS EfficiencyPercent,
    
    -- Stato
    CASE 
        WHEN po.ActualQuantity >= po.PlannedQuantity THEN 'Completo'
        WHEN po.ActualQuantity > 0 THEN 'In Corso'
        ELSE 'Pianificato'
    END AS Status
    
FROM Fact.ProductionOrders po
INNER JOIN Dim.Product p ON po.ProductKey = p.ProductKey
INNER JOIN Dim.WorkCenter w ON po.WorkCenterKey = w.WorkCenterKey
INNER JOIN Dim.Employee e ON po.OperatorKey = e.EmployeeKey
INNER JOIN Dim.Date d ON po.ProductionDateKey = d.DateKey
WHERE po.IsDeleted = 0
    AND p.IsDeleted = 0
    AND w.IsDeleted = 0;
```

**Utilizzo dall'Applicazione**:
```sql
-- L'applicazione ERP si connette come utente dw_erp
-- Può accedere solo allo schema vERP

SELECT 
    ProductionDate,
    ProductCode,
    SUM(ActualQuantity) AS TotalProduced
FROM vERP.ProductionOrders
WHERE ProductionDate >= '2026-05-01'
GROUP BY ProductionDate, ProductCode
ORDER BY ProductionDate, ProductCode;
```

## Pattern di Sincronizzazione

### Sincronizzazione Dimensioni

Il pattern di sincronizzazione per le dimensioni rispecchia il pattern Landing:

```sql
-- Passo 1: Creare staging temporaneo dalla vista
SELECT * 
INTO #DimCustomerStaging
FROM Dim.CustomerView;

-- Passo 2: Generare chiavi surrogate per nuovi record
UPDATE s
SET CustomerKey = NEXT VALUE FOR Dim.CustomerSequence
FROM #DimCustomerStaging s
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer t
    WHERE t.CompanyId = s.CompanyId 
    AND t.CustomerId = s.CustomerId
);

-- Passo 3: MERGE nella tabella dimensione
MERGE Dim.Customer AS target
USING #DimCustomerStaging AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Scenario C: Aggiornare record modificati (escludere membri speciali)
WHEN MATCHED 
    AND target.ChangeHashKey <> source.ChangeHashKey 
    AND target.CustomerKey NOT IN (-1, -101) THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        Name = source.Name,
        TaxIdentifier = source.TaxIdentifier,
        Category = source.Category,
        Region = source.Region,
        CustomerSegment = source.CustomerSegment

-- Scenario A: Inserire nuovi record
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        CustomerKey, CompanyId, CustomerId, ChangeHashKey, 
        InsertDatetime, UpdateDatetime, IsDeleted,
        Name, TaxIdentifier, Category, Region, CustomerSegment
    )
    VALUES (
        source.CustomerKey, source.CompanyId, source.CustomerId, 
        source.ChangeHashKey, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
        source.Name, source.TaxIdentifier, source.Category, 
        source.Region, source.CustomerSegment
    )

-- Scenario D: Eliminazione soft record mancanti (escludere membri speciali)
WHEN NOT MATCHED BY SOURCE 
    AND target.IsDeleted = 0 
    AND target.CustomerKey NOT IN (-1, -101) THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

**Differenze Chiave dalla Landing**:
1. **Generazione Chiave Surrogata**: I nuovi record ottengono chiavi dalla sequence prima del MERGE
2. **Protezione Membri Speciali**: MERGE esclude CustomerKey IN (-1, -101) per prevenire modifiche
3. **Vista come Sorgente**: #DimCustomerStaging popolato da Dim.CustomerView

### Sincronizzazione Fatti

La sincronizzazione delle tabelle dei fatti segue lo stesso pattern:

```sql
-- Passo 1: Creare staging temporaneo dalla vista
SELECT * 
INTO #FactSalesStaging
FROM Fact.SalesView;

-- Passo 2: MERGE nella tabella fatti
MERGE Fact.Sales AS target
USING #FactSalesStaging AS source
    ON target.CompanyId = source.CompanyId 
    AND target.OrderId = source.OrderId 
    AND target.LineNumber = source.LineNumber

-- Scenario C: Aggiornare record modificati
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerKey = source.CustomerKey,
        ProductKey = source.ProductKey,
        OrderDateKey = source.OrderDateKey,
        SalesPersonKey = source.SalesPersonKey,
        OrderNumber = source.OrderNumber,
        InvoiceNumber = source.InvoiceNumber,
        Quantity = source.Quantity,
        UnitPrice = source.UnitPrice,
        DiscountPercent = source.DiscountPercent,
        LineTotal = source.LineTotal,
        TaxAmount = source.TaxAmount,
        NetAmount = source.NetAmount,
        DiscountAmount = source.DiscountAmount

-- Scenario A: Inserire nuovi record
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        CompanyId, OrderId, LineNumber, ChangeHashKey,
        InsertDatetime, UpdateDatetime, IsDeleted,
        CustomerKey, ProductKey, OrderDateKey, SalesPersonKey,
        OrderNumber, InvoiceNumber,
        Quantity, UnitPrice, DiscountPercent, 
        LineTotal, TaxAmount, NetAmount, DiscountAmount
    )
    VALUES (
        source.CompanyId, source.OrderId, source.LineNumber, 
        source.ChangeHashKey,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
        source.CustomerKey, source.ProductKey, source.OrderDateKey, 
        source.SalesPersonKey,
        source.OrderNumber, source.InvoiceNumber,
        source.Quantity, source.UnitPrice, source.DiscountPercent,
        source.LineTotal, source.TaxAmount, source.NetAmount, 
        source.DiscountAmount
    )

-- Scenario D: Eliminazione soft record mancanti
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

### Ordine di Sincronizzazione

Eseguire le sincronizzazioni in **ordine di dipendenza**:

```
1. Tabelle Staging (se necessarie)
   ↓
2. Dimensioni (in ordine di dipendenza)
   ↓
3. Tabelle Bridge (dopo le dimensioni)
   ↓
4. Tabelle Fatti (dopo dimensioni e bridge)
   ↓
5. Viste Applicative (riflettono automaticamente i cambiamenti)
```

**Esempio**:
```sql
-- 1. Staging
EXEC Staging.UpdateCustomerRegion;

-- 2. Dimensioni (prima le indipendenti, poi le dipendenti)
EXEC Dim.SynchronizeCustomerCategory;
EXEC Dim.SynchronizeCustomer;  -- dipende da CustomerCategory
EXEC Dim.SynchronizeProduct;
EXEC Dim.SynchronizeEmployee;
EXEC Dim.SynchronizeDate;

-- 3. Tabelle Bridge
EXEC Bridge.SynchronizeProductCategory;

-- 4. Tabelle Fatti
EXEC Fact.SynchronizeSales;
```

## Benefici e Giustificazione

### Perché Modellazione Dimensionale?

**Schema Normalizzato Tradizionale** (3NF):
```
Orders → Customers → CustomerTypes
      → OrderLines → Products → ProductCategories
                  → Suppliers → SupplierRegions
```
**Problemi per Analytics**:
- Join multi-tabella complessi per domande semplici
- Difficile da comprendere per gli utenti di business
- Prestazioni query scarse per aggregazioni
- Difficile aggiungere nuove misure o attributi

**Modello Dimensionale** (Schema a Stella):
```
      Customer Dim ─┐
         Product Dim ┼─→ Sales Fact
            Date Dim ─┘
```
**Vantaggi per Analytics**:
- ✅ Struttura intuitiva (rispecchia pensiero business)
- ✅ Query semplici (join minimi)
- ✅ Prestazioni eccellenti (chiavi esterne indicizzate)
- ✅ Flessibile (facile aggiungere dimensioni/misure)
- ✅ Consistente (dimensioni conformate)

### Perché Chiavi Surrogate?

**Problemi Chiave Naturale**:
- Cambiano nel tempo (riassegnazione ID cliente)
- Chiavi composite (CustomerID + CompanyID)
- Formati diversi tra sorgenti (SAP vs Salesforce)
- Chiavi stringa (prestazioni scarse)

**Benefici Chiave Surrogata**:
- ✅ Non cambiano mai (riferimenti fatti stabili)
- ✅ Singolo intero (prestazioni ottimali)
- ✅ Indipendente dalla sorgente (friendly integrazione)
- ✅ Abilitano tracciamento storico (SCD Tipo 2)
- ✅ Tabelle fatti più piccole (chiavi esterne compatte)

### Perché Membri Speciali?

**Problemi Chiave Esterna NULL**:
```sql
-- Query senza membri speciali
SELECT 
    ISNULL(c.CustomerName, '(Nessun Cliente)') AS Customer,
    SUM(s.LineTotal) AS Sales
FROM Fact.Sales s
LEFT JOIN Dim.Customer c ON s.CustomerKey = c.CustomerKey
GROUP BY c.CustomerName;
```
**Problemi**:
- Outer join in ogni query (complessità + prestazioni)
- Gestione NULL in ogni aggregazione
- Visualizzazione inconsistente dei valori NULL
- Nessun vincolo di integrità referenziale

**Soluzione Membri Speciali**:
```sql
-- Query con membri speciali
SELECT 
    c.CustomerName AS Customer,
    SUM(s.LineTotal) AS Sales
FROM Fact.Sales s
INNER JOIN Dim.Customer c ON s.CustomerKey = c.CustomerKey
GROUP BY c.CustomerName;
```
**Benefici**:
- ✅ Inner join (più semplici, più veloci)
- ✅ Integrità referenziale applicata
- ✅ Rappresentazione NULL consistente ('(Vuoto)', '(Sconosciuto)')
- ✅ Auditing (contare Sconosciuti per trovare problemi qualità dati)
- ✅ Tutti i fatti si caricano (dimensioni mancanti non bloccano caricamento)

### Perché Sincronizzazione Basata su Viste?

**Aggiornamenti Diretti Tabella**:
```sql
-- Logica trasformazione incorporata in procedura
UPDATE Dim.Customer SET Name = ...
```
**Problemi**:
- Logica nascosta in codice procedurale
- Difficile testare trasformazioni
- Difficile verificare "stato corrente"
- Non si può interrogare risultati trasformazione prima del commit

**Approccio Basato su Viste**:
```sql
-- Logica nella vista (SQL dichiarativo)
CREATE VIEW Dim.CustomerView AS ...
-- Materializzare nella tabella
MERGE Dim.Customer ... USING Dim.CustomerView
```
**Benefici**:
- ✅ Logica trasformazione visibile (SELECT dalla vista)
- ✅ Facile da testare (confrontare vista vs tabella)
- ✅ Pattern consistente (stesso della Landing)
- ✅ Può interrogare vista indipendentemente
- ✅ Chiara separazione delle responsabilità

### Perché Schemi Applicativi?

**Accesso Diretto a Tabelle Core**:
```sql
-- ERP interroga Fact.ProductionOrders direttamente
GRANT SELECT ON Fact.ProductionOrders TO dw_erp;
```
**Problemi**:
- Rischio sicurezza (applicazione vede tutte colonne/tabelle)
- Accoppiamento stretto (cambiamenti schema rompono applicazioni)
- Nessuna astrazione (non si può cambiare modello sottostante)
- Prestazioni (applicazioni possono scrivere query inefficienti)

**Approccio Schema Applicativo**:
```sql
-- ERP interroga vERP.ProductionOrders (vista curata)
GRANT SELECT ON SCHEMA::vERP TO dw_erp;
```
**Benefici**:
- ✅ Sicurezza (principio del minimo privilegio)
- ✅ Astrazione (può rifattorizzare tabelle sottostanti)
- ✅ Semplificazione (logica complessa nascosta nelle viste)
- ✅ Ottimizzazione (viste indicizzate se necessario)
- ✅ Versionamento (mantenere vecchia vista durante migrazione)

## Esempi

### Esempio 1: Implementazione Dimensione Completa

**Sorgente Landing**:
```sql
-- Landing.ERP.Customer
CompanyId | CustomerId | CustomerName   | VAT      | CategoryId
----------|------------|----------------|----------|------------
1         | 100        | Acme Corp      | IT12345  | 1
1         | 101        | Beta LLC       | IT67890  | 2
```

**Arricchimento Staging**:
```sql
-- Staging.CustomerRegion (derivata da logica codice postale)
CREATE TABLE Staging.CustomerRegion
(
    CustomerId  INT,
    RegionId    INT,
    RegionName  NVARCHAR(50)
);
```

**Vista Dimensione**:
```sql
CREATE VIEW Dim.CustomerView
AS
SELECT
    c.CompanyId,
    c.CustomerId,
    c.ChangeHashKey,
    c.InsertDatetime,
    c.UpdateDatetime,
    c.IsDeleted,
    c.CustomerName AS Name,
    c.VAT AS TaxIdentifier,
    ct.CategoryName AS Category,
    cr.RegionName AS Region
FROM [Landing].[ERP].[Customer] c
LEFT JOIN [Landing].[ERP].[CustomerCategory] ct 
    ON c.CategoryId = ct.CategoryId
LEFT JOIN [Staging].[CustomerRegion] cr 
    ON c.CustomerId = cr.CustomerId
WHERE c.IsDeleted = 0;
```

**Tabella Dimensione Dopo Sync**:
```sql
-- Dim.Customer
CustomerKey | CompanyId | CustomerId | Name          | Category   | Region
------------|-----------|------------|---------------|------------|--------
-1          | -1        | -1         | (Vuoto)       | (Vuoto)    | (Vuoto)
-101        | -101      | -101       | (Sconosciuto) | (Sconosciuto) | (Sconosciuto)
1           | 1         | 100        | Acme Corp     | Premium    | Nord
2           | 1         | 101        | Beta LLC      | Standard   | Sud
```

### Esempio 2: Implementazione Fatti Completa

**Sorgenti Landing**:
```sql
-- Landing.ERP.Order
CompanyId | OrderId | CustomerId | OrderDate  | SalesPersonId
----------|---------|------------|------------|---------------
1         | 1001    | 100        | 2026-05-15 | 5
1         | 1002    | 999        | 2026-05-16 | NULL

-- Landing.ERP.OrderDetail
CompanyId | OrderId | LineNum | ProductId | Quantity | UnitPrice
----------|---------|---------|-----------|----------|----------
1         | 1001    | 1       | 200       | 10       | 50.00
1         | 1002    | 1       | 201       | 5        | 100.00
```

**Tabelle Dimensionali**:
```sql
-- Dim.Customer
CustomerKey | CustomerId
------------|------------
-1          | -1         (Vuoto)
-101        | -101       (Sconosciuto)
1           | 100        (Acme Corp - esiste)
-- Cliente 999 non esiste

-- Dim.Employee
EmployeeKey | EmployeeId
------------|------------
-1          | -1         (Vuoto)
-101        | -101       (Sconosciuto)
10          | 5          (John Doe - esiste)
```

**Vista Fatti**:
```sql
CREATE VIEW Fact.SalesView
AS
SELECT
    od.CompanyId,
    od.OrderId,
    od.LineNumber,
    od.ChangeHashKey,
    od.InsertDatetime,
    od.UpdateDatetime,
    od.IsDeleted,
    
    -- Lookup dimensioni con fallback membri speciali
    COALESCE(dc.CustomerKey, 
        CASE WHEN o.CustomerId IS NULL THEN -1 ELSE -101 END) AS CustomerKey,
    COALESCE(dp.ProductKey, 
        CASE WHEN od.ProductId IS NULL THEN -1 ELSE -101 END) AS ProductKey,
    COALESCE(de.EmployeeKey, 
        CASE WHEN o.SalesPersonId IS NULL THEN -1 ELSE -101 END) AS SalesPersonKey,
    
    od.Quantity,
    od.UnitPrice,
    od.Quantity * od.UnitPrice AS LineTotal
    
FROM [Landing].[ERP].[OrderDetail] od
INNER JOIN [Landing].[ERP].[Order] o 
    ON od.CompanyId = o.CompanyId AND od.OrderId = o.OrderId
LEFT JOIN Dim.Customer dc 
    ON o.CustomerId = dc.CustomerId AND dc.IsDeleted = 0
LEFT JOIN Dim.Product dp 
    ON od.ProductId = dp.ProductId AND dp.IsDeleted = 0
LEFT JOIN Dim.Employee de 
    ON o.SalesPersonId = de.EmployeeId AND de.IsDeleted = 0
WHERE od.IsDeleted = 0;
```

**Tabella Fatti Dopo Sync**:
```sql
-- Fact.Sales
CompanyId | OrderId | LineNum | CustomerKey | SalesPersonKey | ProductKey | Quantity | LineTotal
----------|---------|---------|-------------|----------------|------------|----------|----------
1         | 1001    | 1       | 1           | 10             | 5          | 10       | 500.00
1         | 1002    | 1       | -101        | -1             | 6          | 5        | 500.00
          (Cliente 999 → Sconosciuto)  (NULL → Vuoto)
```

**Query Analisi**:
```sql
-- Vendite per Cliente (inclusi Sconosciuto e Vuoto)
SELECT 
    c.Name AS Customer,
    SUM(f.LineTotal) AS TotalSales,
    COUNT(*) AS OrderCount
FROM Fact.Sales f
INNER JOIN Dim.Customer c ON f.CustomerKey = c.CustomerKey
GROUP BY c.Name;

-- Risultato:
-- Customer        TotalSales  OrderCount
-- Acme Corp       500.00      1
-- (Sconosciuto)   500.00      1  ← Problema qualità dati: Cliente 999 mancante
```

### Esempio 3: Tabella Bridge per Molti-a-Molti

**Scenario**: I prodotti possono appartenere a più categorie

**Dati Landing**:
```sql
-- Landing.ERP.ProductCategoryMapping
ProductId | CategoryId
----------|------------
200       | 1          (Elettronica)
200       | 3          (Accessori)
201       | 1          (Elettronica)
```

**Tabella Bridge**:
```sql
-- Bridge.ProductCategory
ProductKey | CategoryKey | AllocationPercent
-----------|-------------|-------------------
5          | 10          | 50.00
5          | 12          | 50.00
6          | 10          | 100.00
```

**Query con Bridge**:
```sql
-- Vendite per Categoria (con allocazione)
SELECT 
    cat.CategoryName,
    SUM(f.LineTotal * b.AllocationPercent / 100) AS AllocatedSales
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category cat ON b.CategoryKey = cat.CategoryKey
GROUP BY cat.CategoryName;

-- Risultato:
-- CategoryName      AllocatedSales
-- Elettronica       750.00  (500 * 50% + 500 * 100%)
-- Accessori         250.00  (500 * 50%)
```

## Migliori Pratiche

### 1. Progettazione Dimensioni

**Mantenere Dimensioni Denormalizzate**:
```sql
-- Bene: Denormalizzato (schema a stella)
Dim.Customer: CustomerKey, Name, Category, Region, Segment

-- Male: Normalizzato (schema a fiocco di neve)
Dim.Customer: CustomerKey, Name, CategoryKey
Dim.CustomerCategory: CategoryKey, CategoryName, RegionKey
Dim.Region: RegionKey, RegionName
```
**Perché**: Gli schemi a fiocco di neve richiedono più join, riducendo prestazioni query e facilità d'uso.

**Usare Etichette Membri Speciali Significative**:
```sql
-- Bene: Etichettatura chiara
Name = '(Vuoto)'  o '(Non Applicabile)'
Name = '(Sconosciuto)' o '(Riferimento Mancante)'

-- Male: Ambiguo
Name = 'N/A'
Name = 'NULL'
Name = ''
```

**Aggiungere Attributi Conteggio Righe per Aggregazione**:
```sql
-- Aggiungere alla tabella dimensione per conteggio facile
RowCount INT NOT NULL DEFAULT 1

-- Abilita conteggi accurati nei report
SELECT Customer, SUM(RowCount) AS TransactionCount
FROM Fact.Sales f
INNER JOIN Dim.Customer c ON f.CustomerKey = c.CustomerKey
GROUP BY Customer;
```

### 2. Progettazione Tabelle Fatti

**Dichiarare Granularità Esplicitamente**:
```sql
-- Documentare granularità nei commenti
-- GRANULARITÀ: Una riga per linea ordine (CompanyId, OrderId, LineNumber)
CREATE TABLE Fact.Sales (...);

-- Male: Granularità ambigua
-- Potrebbe essere per ordine? Per linea? Per cliente?
```

**Includere Solo Misure Additive in Aggregazioni**:
```sql
-- Bene: Sommare misure additive
SELECT Customer, SUM(LineTotal) AS TotalSales FROM ...

-- Male: Sommare misure non-additive
SELECT Customer, SUM(UnitPrice) AS ??? FROM ...  -- Non ha senso

-- Usare invece AVG per misure non-additive
SELECT Customer, AVG(UnitPrice) AS AvgPrice FROM ...
```

**Preferire Chiavi Surrogate Anche nei Fatti**:
```sql
-- Considerare aggiungere chiave surrogata anche ai fatti (opzionale)
SalesKey BIGINT IDENTITY(1,1) PRIMARY KEY

-- Benefici:
-- - Identificatore riga semplice per riferimenti
-- - Può migliorare prestazioni per alcune query
-- - Utile per tracciare correzioni/aggiustamenti
```

### 3. Strategie di Indicizzazione

**Pattern Indici Standard per Dimensioni**:
```sql
-- Chiave primaria surrogata (clustered)
PRIMARY KEY CLUSTERED (CustomerKey)

-- Indice unico su chiave naturale
UNIQUE NONCLUSTERED (CompanyId, CustomerId)

-- Indice su hash per rilevamento cambiamenti
NONCLUSTERED (ChangeHashKey)
```

**Pattern Indici Standard per Fatti**:
```sql
-- Chiave primaria su chiavi naturali (clustered)
PRIMARY KEY CLUSTERED (CompanyId, OrderId, LineNumber)

-- Indici non-clustered su ciascuna chiave esterna dimensionale
NONCLUSTERED (CustomerKey) INCLUDE (LineTotal, Quantity)
NONCLUSTERED (ProductKey) INCLUDE (LineTotal, Quantity)
NONCLUSTERED (OrderDateKey) INCLUDE (LineTotal, Quantity)

-- Indici per pattern query comuni
NONCLUSTERED (OrderDateKey, CustomerKey) INCLUDE (LineTotal)
```

### 4. Gestione Membri Speciali

**Non Modificare Mai Membri Speciali**:
```sql
-- Sempre escludere membri speciali da aggiornamenti
MERGE Dim.Customer AS target
...
WHEN MATCHED 
    AND target.CustomerKey NOT IN (-1, -101)  -- CRITICO
    AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET ...
```

**Monitorare Membri Sconosciuti**:
```sql
-- Creare vista di monitoraggio qualità dati
CREATE VIEW audit.vw_UnknownReferences
AS
SELECT 
    'Customer' AS Dimension,
    COUNT(*) AS UnknownCount,
    SUM(f.LineTotal) AS AffectedAmount
FROM Fact.Sales f
WHERE f.CustomerKey = -101

UNION ALL

SELECT 
    'Product' AS Dimension,
    COUNT(*) AS UnknownCount,
    SUM(f.LineTotal) AS AffectedAmount
FROM Fact.Sales f
WHERE f.ProductKey = -101;
```

### 5. Test e Validazione

**Validare Integrità Referenziale**:
```sql
-- Verificare che tutti i fatti abbiano chiavi esterne valide
SELECT 'Chiavi Customer Orfane' AS Problema, COUNT(*) AS Conteggio
FROM Fact.Sales f
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer c WHERE c.CustomerKey = f.CustomerKey
);
```

**Confrontare Vista vs Tabella**:
```sql
-- Verificare che tabella rispecchi vista
SELECT 'Solo in Vista' AS Fonte, COUNT(*) AS Conteggio
FROM Dim.CustomerView v
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer t 
    WHERE t.CompanyId = v.CompanyId AND t.CustomerId = v.CustomerId
)
UNION ALL
SELECT 'Solo in Tabella' AS Fonte, COUNT(*) AS Conteggio
FROM Dim.Customer t
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.CustomerView v 
    WHERE v.CompanyId = t.CompanyId AND v.CustomerId = t.CustomerId
)
AND t.CustomerKey NOT IN (-1, -101);  -- Escludere membri speciali
```

---

## Riepilogo

Questo pattern di progettazione Data Warehouse fornisce:

✅ **Intuibilità**: Modello dimensionale rispecchia pensiero business  
✅ **Prestazioni**: Schema a stella ottimizzato per query analitiche  
✅ **Integrità**: Membri speciali garantiscono integrità referenziale  
✅ **Flessibilità**: Viste basate su trasformazioni adattabili  
✅ **Sicurezza**: Schemi applicativi isolano accesso  
✅ **Manutenibilità**: Pattern consistenti e struttura chiara  

Seguendo questi principi, crei un data warehouse robusto che trasforma dati grezzi in insight analitici mentre mantiene integrità, prestazioni e facilità d'uso.

---

**Versione Documento**: 1.0  
**Ultimo Aggiornamento**: 20 maggio 2026  
**Stack Tecnologico**: Microsoft SQL Server 2016+, Metodologia Kimball
