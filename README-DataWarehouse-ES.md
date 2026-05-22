# Data Warehouse - Patrón de Diseño

## Tabla de Contenidos
- [Visión General](#visión-general)
- [Arquitectura](#arquitectura)
- [Conceptos Clave](#conceptos-clave)
- [Diseño de Esquema](#diseño-de-esquema)
- [Tablas de Dimensión](#tablas-de-dimensión)
- [Tablas de Hechos](#tablas-de-hechos)
- [Tablas Puente](#tablas-puente)
- [Vistas de Aplicación](#vistas-de-aplicación)
- [Patrón de Sincronización](#patrón-de-sincronización)
- [Beneficios y Justificación](#beneficios-y-justificación)
- [Ejemplos](#ejemplos)
- [Mejores Prácticas](#mejores-prácticas)

## Visión General

La capa **Data Warehouse** es el núcleo analítico de la plataforma de datos donde los datos crudos provenientes de la zona Landing se transforman en un modelo dimensional optimizado para business intelligence y reporting. Este documento describe un patrón probado para diseñar y gestionar un data warehouse utilizando Microsoft SQL Server y modelado dimensional estilo Kimball.

### Propósito del Data Warehouse

La capa Data Warehouse cumple varias funciones críticas:
- **Modelado Dimensional**: Organiza los datos en hechos y dimensiones para consultas intuitivas
- **Integración de Datos**: Combina datos de múltiples sistemas fuente en entidades de negocio unificadas
- **Normalización**: Estandariza nombres de columnas, tipos de datos y reglas de negocio entre fuentes
- **Rendimiento**: Optimiza estructuras de datos para consultas analíticas y reporting
- **Lógica de Negocio**: Implementa medidas calculadas, jerarquías y reglas de negocio
- **Control de Acceso**: Proporciona vistas seguras y específicas de datos analíticos para aplicaciones

## Arquitectura

### Estructura de la Base de Datos

```
Base de Datos DataWarehouse
├── Staging (esquema)
│   ├── CustomerStaging (cálculos intermedios)
│   ├── OrderEnrichment (transformaciones parciales)
│   └── ... (otras tablas staging)
├── Dim (esquema)
│   ├── Customer (tabla de dimensión)
│   ├── CustomerView (vista fuente para sincronización)
│   ├── Product (tabla de dimensión)
│   ├── ProductView (vista fuente para sincronización)
│   └── ... (otras dimensiones)
├── Fact (esquema)
│   ├── Sales (tabla de hechos)
│   ├── SalesView (vista fuente para sincronización)
│   ├── Production (tabla de hechos)
│   ├── ProductionView (vista fuente para sincronización)
│   └── ... (otros hechos)
├── Bridge (esquema)
│   ├── ProductCategory (puente muchos-a-muchos)
│   ├── CustomerGroup (puente muchos-a-muchos)
│   └── ... (otros puentes)
├── vERP (esquema - vistas de aplicación)
│   ├── ProductionOrders (vista para consumo ERP)
│   ├── Customers (vista para consumo ERP)
│   └── ... (otras vistas ERP)
├── vPowerBI (esquema - vistas de aplicación)
│   ├── SalesAnalysis (vista para Power BI)
│   └── ... (otras vistas BI)
└── ... (esquemas de aplicación adicionales)
```

### Flujo de Datos

```
┌─────────────────────────────────────────────────────────────┐
│                    Base de Datos Landing                    │
│         (esquemas ERP, SALESFORCE, MES)                     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Esquema Staging                           │
│        (Cálculos y transformaciones intermedias)            │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌──────────────────┐           ┌──────────────────┐
│  Esquema Dim     │           │  Esquema Fact    │
│  (Dimensiones)   │◄──────────┤  (Hechos)        │
└────────┬─────────┘           └────────┬─────────┘
         │                              │
         └───────────┬──────────────────┘
                     │
                     ▼
         ┌────────────────────────┐
         │   Esquema Bridge       │
         │  (Muchos-a-Muchos)     │
         └────────┬───────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│          Vistas de Aplicación (vERP, vPowerBI)              │
│     (Vistas seguras y curadas para consumidores específicos)│
└─────────────────────────────────────────────────────────────┘
```

### Principios de Diseño

1. **Modelado Dimensional Kimball**: Esquema en estrella con hechos y dimensiones
2. **Separación de Responsabilidades**: Staging, dimensiones, hechos, puentes y vistas de aplicación en esquemas separados
3. **Sincronización Basada en Vistas**: Las vistas fuente definen lógica de transformación; las tablas almacenan resultados materializados
4. **Claves Sustitutas**: Claves enteras generadas desde secuencias para todas las dimensiones
5. **Miembros Especiales**: Manejo estándar de claves foráneas NULL y desconocidas
6. **Integridad Referencial**: Aplicación estricta mediante miembros especiales y lógica de sincronización

## Conceptos Clave

### Modelado Dimensional Kimball

La **metodología Kimball** es un enfoque bottom-up para diseño de data warehouse que se enfoca en:
- **Esquema en Estrella**: Tablas de hechos en el centro rodeadas por tablas de dimensión
- **Enfoque en Procesos de Negocio**: Modelar procesos de negocio (ej. Ventas, Producción) como hechos
- **Dimensiones Conformadas**: Dimensiones compartidas entre múltiples tablas de hechos
- **Declaración de Granularidad**: Definición explícita de la granularidad de tablas de hechos

**Beneficios**:
- Intuitivo para usuarios de negocio
- Optimizado para rendimiento de consultas
- Flexible para análisis ad-hoc
- Enfoque de desarrollo incremental

### Tablas de Hechos vs Dimensiones

**Tablas de Dimensión** (QUIÉN, QUÉ, DÓNDE, CUÁNDO, POR QUÉ):
- Atributos descriptivos sobre entidades de negocio
- Ejemplos: Customer, Product, Date, Location
- Relativamente pequeñas (miles a millones de filas)
- Tablas anchas (muchas columnas)
- Cambian lentamente con el tiempo

**Tablas de Hechos** (MÉTRICAS, MEDIDAS):
- Medidas numéricas de eventos de negocio
- Ejemplos: Transacciones de venta, Órdenes de producción, Clics web
- Muy grandes (millones a miles de millones de filas)
- Tablas angostas (claves foráneas + medidas)
- Solo en adición o snapshots periódicos

### Claves Sustitutas

Una **clave sustituta** es un identificador artificial que no tiene significado de negocio:
```sql
CustomerKey INT  -- Clave sustituta (secuencia generada)
vs
CustomerId INT   -- Clave natural/de negocio (del sistema fuente)
```

**¿Por Qué Usar Claves Sustitutas?**
- **Independencia**: Desacopla el warehouse de cambios del sistema fuente
- **Integración**: Combina datos de múltiples fuentes con claves diferentes
- **Rendimiento**: Las claves enteras son más rápidas que claves compuestas o de cadena
- **Historial**: Habilita seguimiento de cambios de dimensión (SCD Tipo 2)
- **Simplicidad**: Claves foráneas de una sola columna en tablas de hechos

**Generación**: 
```sql
-- Usando SEQUENCE de SQL Server
CREATE SEQUENCE Dim.CustomerSequence START WITH 1 INCREMENT BY 1;
CustomerKey = NEXT VALUE FOR Dim.CustomerSequence
```

### Miembros Especiales (Vacío y Desconocido)

Cada dimensión contiene **dos registros especiales**:

**Miembro Vacío (Clave = -1)**:
- Representa claves foráneas NULL en tablas de hechos
- Usado cuando la dimensión no es aplicable
- Ejemplo: OrderKey = -1 cuando Customer no tiene órdenes

**Miembro Desconocido (Clave = -101)**:
- Representa claves foráneas no emparejadas en tablas de hechos
- Usado cuando existe clave de negocio pero falta el registro de dimensión o está eliminado
- Ejemplo: CustomerKey = -101 cuando OrderCustomerId = 999 pero Customer 999 no existe o IsDeleted = 1

**Beneficios**:
- **Preserva Datos**: Los registros de hechos se cargan incluso con referencias de dimensión faltantes
- **Integridad Referencial**: Sin claves foráneas NULL; todos los hechos referencian dimensiones válidas
- **Auditoría**: Puede identificar problemas de calidad de datos (recuento de miembros Desconocidos)
- **Simplicidad de Consultas**: No se necesitan outer joins o manejo de NULL en reportes

### Dimensiones de Cambio Lento (SCD)

Este patrón implementa **SCD Tipo 1** (sobrescritura):
- Solo valor actual (sin seguimiento de historial)
- Las actualizaciones de dimensión sobrescriben valores existentes
- Simple y eficiente
- Adecuado cuando no se necesitan valores históricos de dimensión

**Enfoques alternativos** (no implementados en este patrón):
- **SCD Tipo 2**: Seguir historial completo con fechas efectivas y flags actuales
- **SCD Tipo 3**: Seguir historial limitado (ej. valor actual y anterior)

### Sincronización Basada en Vistas

El patrón de sincronización usa **vistas como fuentes** y **tablas como destinos**:

```
Tablas Landing → Vista de Dimensión → Tabla de Dimensión
```

**Vista de Dimensión**: 
- Define lógica de transformación (joins, cálculos, normalización)
- Actúa como "estado deseado" de la dimensión

**Tabla de Dimensión**: 
- Snapshot materializado de la vista
- Optimizada con índices para rendimiento de consultas
- Actualizada mediante el mismo patrón MERGE que Landing

**Beneficios**:
- Clara separación entre lógica (vista) y almacenamiento (tabla)
- Las vistas pueden probarse independientemente
- Las tablas proporcionan rendimiento consistente
- Mismo patrón de sincronización en todo el warehouse

### Patrón LEFT JOIN para Hechos

Las vistas de hechos usan **LEFT JOIN** a dimensiones para asegurar que todos los hechos se carguen:

```sql
SELECT
    f.*,
    COALESCE(d.CustomerKey, -101) AS CustomerKey  -- Desconocido si no hay coincidencia
FROM Landing.ERP.Order f
LEFT JOIN Dim.Customer d 
    ON f.CustomerId = d.CustomerId
    AND d.IsDeleted = 0
```

**Lógica**:
- **Inner join emparejado**: Usar clave sustituta de la dimensión
- **Clave foránea NULL**: Usar -1 (miembro vacío)
- **Sin coincidencia o eliminado**: Usar -101 (miembro desconocido)

## Diseño de Esquema

### Convenciones de Nomenclatura

| Elemento | Convención | Ejemplo |
|---------|-----------|---------|
| Base de Datos | PascalCase | `DataWarehouse` |
| Esquema | PascalCase | `Dim`, `Fact`, `Bridge`, `Staging` |
| Esquema de Aplicación | Prefijo minúscula + PascalCase | `vERP`, `vPowerBI` |
| Tabla de Dimensión | Nombre singular | `Customer`, `Product` |
| Vista de Dimensión | Nombre tabla + "View" | `CustomerView`, `ProductView` |
| Tabla de Hechos | Plural o nombre proceso | `Sales`, `ProductionOrders` |
| Vista de Hechos | Nombre tabla + "View" | `SalesView`, `ProductionOrdersView` |
| Clave Sustituta | Nombre dimensión + "Key" | `CustomerKey`, `ProductKey` |
| Clave Natural | Coincide con fuente | `CustomerId`, `ProductId` |
| Secuencia | Esquema + Tabla + "Sequence" | `DimCustomerSequence` |

### Organización de Esquemas

**Esquema Staging**:
- Propósito: Transformaciones intermedias, cálculos complejos
- Visibilidad: Solo interna a procesos ETL
- Ciclo de vida: Las tablas pueden truncarse/recrearse frecuentemente
- Ejemplos: Joins complejos, agregaciones, aplicación de reglas de negocio

**Esquema Dim**:
- Propósito: Tablas de dimensión y sus vistas fuente
- Visibilidad: Consumidas por vistas de hechos y vistas de aplicación
- Ciclo de vida: Persistente, sincronizado con cambios de Landing

**Esquema Fact**:
- Propósito: Tablas de hechos y sus vistas fuente
- Visibilidad: Consumidas por vistas de aplicación
- Ciclo de vida: Solo en adición o snapshots periódicos

**Esquema Bridge**:
- Propósito: Relaciones muchos-a-muchos entre hechos y dimensiones
- Visibilidad: Consumidas por vistas de aplicación
- Ciclo de vida: Sincronizado con cambios de dimensión

**Esquemas de Aplicación (vERP, vPowerBI, etc.)**:
- Propósito: Vistas curadas para aplicaciones o grupos de usuarios específicos
- Visibilidad: Externa al data warehouse (consumida por aplicaciones)
- Ciclo de vida: Interfaces estables (versionadas si hay cambios breaking)

## Tablas de Dimensión

### Estructura

Cada dimensión sigue este patrón:

**Vista de Dimensión** (define la transformación):
```sql
CREATE VIEW Dim.CustomerView
AS
SELECT
    -- Clave Sustituta (será generada durante sincronización)
    -- NEXT VALUE FOR Dim.CustomerSequence AS CustomerKey
    
    -- Claves Naturales (de la fuente)
    c.CompanyId,
    c.CustomerId,
    
    -- Columnas Técnicas (de Landing)
    c.ChangeHashKey,
    c.InsertDatetime,
    c.UpdateDatetime,
    c.IsDeleted,
    
    -- Atributos de Negocio (normalizados)
    c.CustomerName AS Name,
    c.VAT AS TaxIdentifier,
    ct.CategoryName AS Category,
    cr.RegionName AS Region,
    
    -- Atributos Calculados
    CASE 
        WHEN c.CreditLimit > 100000 THEN 'Alto Valor'
        WHEN c.CreditLimit > 10000 THEN 'Medio Valor'
        ELSE 'Estándar'
    END AS CustomerSegment
    
FROM [Landing].[ERP].[Customer] c
LEFT JOIN [Landing].[ERP].[CustomerCategory] ct 
    ON c.CategoryId = ct.CategoryId
LEFT JOIN [Staging].[CustomerRegion] cr 
    ON c.RegionId = cr.RegionId
WHERE c.IsDeleted = 0  -- Solo registros activos
```

**Tabla de Dimensión** (almacenamiento materializado):
```sql
CREATE TABLE Dim.Customer
(
    -- Clave Sustituta
    CustomerKey         INT             NOT NULL,
    
    -- Claves Naturales
    CompanyId           INT             NOT NULL,
    CustomerId          INT             NOT NULL,
    
    -- Columnas Técnicas
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL,
    UpdateDatetime      DATETIME        NOT NULL,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Atributos de Negocio
    Name                NVARCHAR(100)   NOT NULL,
    TaxIdentifier       NVARCHAR(20)    NULL,
    Category            NVARCHAR(50)    NULL,
    Region              NVARCHAR(50)    NULL,
    CustomerSegment     NVARCHAR(20)    NULL,
    
    -- Clave Primaria en Sustituta
    CONSTRAINT PK_Dim_Customer PRIMARY KEY CLUSTERED (CustomerKey),
    
    -- Restricción única en Clave Natural
    CONSTRAINT UQ_Dim_Customer_NaturalKey UNIQUE (CompanyId, CustomerId)
);

-- Índice para sincronización (búsqueda clave natural)
CREATE NONCLUSTERED INDEX IX_Dim_Customer_NaturalKey 
    ON Dim.Customer (CompanyId, CustomerId);

-- Índice para detección de cambios
CREATE NONCLUSTERED INDEX IX_Dim_Customer_ChangeHash 
    ON Dim.Customer (ChangeHashKey);
```

**Secuencia** (generación clave sustituta):
```sql
CREATE SEQUENCE Dim.CustomerSequence 
    START WITH 1 
    INCREMENT BY 1;
```

### Inicialización de Miembros Especiales

Cada dimensión debe inicializarse con miembros especiales:

```sql
-- Inicializar secuencia más allá de claves de miembros especiales
ALTER SEQUENCE Dim.CustomerSequence RESTART WITH 1;

-- Insertar Miembro Vacío (Clave = -1)
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
    -1,                                  -- Clave miembro vacío
    -1,
    -1,
    0x00,                                -- Hash vacío
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0,                                   -- Nunca eliminado
    '(Vacío)',
    NULL,
    '(Vacío)',
    '(Vacío)',
    '(Vacío)'
);

-- Insertar Miembro Desconocido (Clave = -101)
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
    -101,                                -- Clave miembro desconocido
    -101,
    -101,
    0x00,                                -- Hash vacío
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0,                                   -- Nunca eliminado
    '(Desconocido)',
    NULL,
    '(Desconocido)',
    '(Desconocido)',
    '(Desconocido)'
);
```

### Tipos de Columnas de Dimensión

**Clave Sustituta (CustomerKey)**:
- Generada desde secuencia
- Nunca cambia
- Clave primaria de tabla de dimensión
- Clave foránea en tablas de hechos

**Claves Naturales (CompanyId, CustomerId)**:
- Identificadores de negocio del sistema fuente
- Usados para búsquedas durante sincronización
- Restricción única aplicada

**Columnas Técnicas (ChangeHashKey, InsertDatetime, UpdateDatetime, IsDeleted)**:
- Heredadas de la capa Landing
- Mismo propósito y uso
- Habilitan detección de cambios y auditoría

**Atributos de Negocio (Name, Category, Region, etc.)**:
- Columnas descriptivas para análisis
- Nombres normalizados (ej. CustomerName → Name)
- Pueden combinar datos de múltiples fuentes
- Pueden incluir valores calculados/derivados

## Tablas de Hechos

### Estructura

Cada tabla de hechos sigue este patrón:

**Vista de Hechos** (define la transformación):
```sql
CREATE VIEW Fact.SalesView
AS
SELECT
    -- Claves Naturales (de la fuente)
    o.CompanyId,
    o.OrderId,
    o.LineNumber,
    
    -- Columnas Técnicas (de Landing)
    o.ChangeHashKey,
    o.InsertDatetime,
    o.UpdateDatetime,
    o.IsDeleted,
    
    -- Claves Foráneas de Dimensión (claves sustitutas vía LEFT JOIN)
    COALESCE(dc.CustomerKey, 
        CASE WHEN o.CustomerId IS NULL THEN -1 ELSE -101 END) AS CustomerKey,
    COALESCE(dp.ProductKey, 
        CASE WHEN o.ProductId IS NULL THEN -1 ELSE -101 END) AS ProductKey,
    COALESCE(dd.DateKey, -101) AS OrderDateKey,
    COALESCE(de.EmployeeKey, 
        CASE WHEN o.SalesPersonId IS NULL THEN -1 ELSE -101 END) AS SalesPersonKey,
    
    -- Dimensiones Degeneradas (atributos alta cardinalidad almacenados en hecho)
    o.OrderNumber,
    o.InvoiceNumber,
    
    -- Medidas (hechos numéricos)
    o.Quantity,
    o.UnitPrice,
    o.DiscountPercent,
    o.LineTotal,
    o.TaxAmount,
    
    -- Medidas Calculadas
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

**Tabla de Hechos** (almacenamiento materializado):
```sql
CREATE TABLE Fact.Sales
(
    -- Claves Naturales (definición granularidad)
    CompanyId           INT             NOT NULL,
    OrderId             INT             NOT NULL,
    LineNumber          INT             NOT NULL,
    
    -- Columnas Técnicas
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL,
    UpdateDatetime      DATETIME        NOT NULL,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Claves Foráneas de Dimensión (claves sustitutas)
    CustomerKey         INT             NOT NULL,
    ProductKey          INT             NOT NULL,
    OrderDateKey        INT             NOT NULL,
    SalesPersonKey      INT             NOT NULL,
    
    -- Dimensiones Degeneradas
    OrderNumber         NVARCHAR(50)    NOT NULL,
    InvoiceNumber       NVARCHAR(50)    NULL,
    
    -- Medidas
    Quantity            DECIMAL(18,2)   NOT NULL,
    UnitPrice           DECIMAL(18,2)   NOT NULL,
    DiscountPercent     DECIMAL(5,2)    NOT NULL,
    LineTotal           DECIMAL(18,2)   NOT NULL,
    TaxAmount           DECIMAL(18,2)   NOT NULL,
    NetAmount           DECIMAL(18,2)   NOT NULL,
    DiscountAmount      DECIMAL(18,2)   NOT NULL,
    
    -- Clave Primaria (granularidad natural)
    CONSTRAINT PK_Fact_Sales PRIMARY KEY CLUSTERED 
        (CompanyId, OrderId, LineNumber),
    
    -- Claves Foráneas a Dimensiones
    CONSTRAINT FK_Fact_Sales_Customer 
        FOREIGN KEY (CustomerKey) REFERENCES Dim.Customer (CustomerKey),
    CONSTRAINT FK_Fact_Sales_Product 
        FOREIGN KEY (ProductKey) REFERENCES Dim.Product (ProductKey),
    CONSTRAINT FK_Fact_Sales_Date 
        FOREIGN KEY (OrderDateKey) REFERENCES Dim.Date (DateKey),
    CONSTRAINT FK_Fact_Sales_Employee 
        FOREIGN KEY (SalesPersonKey) REFERENCES Dim.Employee (EmployeeKey)
);

-- Índices para patrones de consulta comunes
CREATE NONCLUSTERED INDEX IX_Fact_Sales_Customer 
    ON Fact.Sales (CustomerKey) INCLUDE (LineTotal, Quantity);

CREATE NONCLUSTERED INDEX IX_Fact_Sales_Product 
    ON Fact.Sales (ProductKey) INCLUDE (LineTotal, Quantity);

CREATE NONCLUSTERED INDEX IX_Fact_Sales_Date 
    ON Fact.Sales (OrderDateKey) INCLUDE (LineTotal, Quantity);
```

### Tipos de Columnas de Hechos

**Claves Naturales (CompanyId, OrderId, LineNumber)**:
- Definen la granularidad (nivel de detalle) del hecho
- Clave primaria de tabla de hechos
- Usadas para sincronización y deduplicación

**Claves Foráneas de Dimensión (CustomerKey, ProductKey, etc.)**:
- Claves sustitutas de tablas de dimensión
- Siempre pobladas (nunca NULL) usando miembros especiales
- Habilitan joins de esquema en estrella

**Dimensiones Degeneradas (OrderNumber, InvoiceNumber)**:
- Identificadores de transacción de alta cardinalidad
- No justifican tabla de dimensión separada
- Almacenadas directamente en tabla de hechos

**Medidas (Quantity, UnitPrice, LineTotal, etc.)**:
- Valores numéricos para agregar
- Soportan operaciones SUM, AVG, MIN, MAX, COUNT
- Pueden ser almacenadas (de fuente) o calculadas (derivadas)

**Medidas Aditivas vs No-Aditivas**:
- **Aditivas**: Pueden sumarse en todas las dimensiones (ej. Quantity, LineTotal)
- **Semi-Aditivas**: Pueden sumarse en algunas dimensiones (ej. Saldo de Cuenta - no en tiempo)
- **No-Aditivas**: No pueden sumarse (ej. Precio Unitario, Ratios) - usar AVG o medidas calculadas

## Tablas Puente

### Propósito

Las tablas puente resuelven **relaciones muchos-a-muchos** entre hechos y dimensiones:

**Escenarios**:
- Product pertenece a múltiples Categories
- Customer pertenece a múltiples Groups
- Employee reporta a múltiples Managers (organización matricial)
- Transaction etiquetada con múltiples Hashtags

### Estructura

```sql
-- Tabla Puente
CREATE TABLE Bridge.ProductCategory
(
    ProductKey          INT             NOT NULL,
    CategoryKey         INT             NOT NULL,
    
    -- Ponderación opcional para asignación
    AllocationPercent   DECIMAL(5,2)    NULL,
    
    -- Columnas Técnicas
    InsertDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdateDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Clave Primaria
    CONSTRAINT PK_Bridge_ProductCategory 
        PRIMARY KEY CLUSTERED (ProductKey, CategoryKey),
    
    -- Claves Foráneas
    CONSTRAINT FK_Bridge_ProductCategory_Product 
        FOREIGN KEY (ProductKey) REFERENCES Dim.Product (ProductKey),
    CONSTRAINT FK_Bridge_ProductCategory_Category 
        FOREIGN KEY (CategoryKey) REFERENCES Dim.Category (CategoryKey)
);

-- Índices para consultas en ambas direcciones
CREATE NONCLUSTERED INDEX IX_Bridge_ProductCategory_Category 
    ON Bridge.ProductCategory (CategoryKey, ProductKey);
```

### Uso en Consultas

```sql
-- Encontrar todos los productos en una categoría (dirección uno-a-muchos)
SELECT 
    c.CategoryName,
    p.ProductName,
    f.LineTotal
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category c ON b.CategoryKey = c.CategoryKey
INNER JOIN Dim.Product p ON f.ProductKey = p.ProductKey
WHERE c.CategoryName = 'Electrónica';

-- Asignar ventas a múltiples categorías (muchos-a-muchos con ponderación)
SELECT 
    c.CategoryName,
    SUM(f.LineTotal * b.AllocationPercent / 100) AS AllocatedSales
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category c ON b.CategoryKey = c.CategoryKey
GROUP BY c.CategoryName;
```

## Vistas de Aplicación

### Propósito

Los esquemas específicos de aplicación proporcionan **vistas curadas y seguras** para consumo externo:

**Beneficios**:
- **Seguridad**: Cada aplicación tiene su propio usuario con permisos restringidos
- **Simplificación**: Joins y lógica complejos ocultos a consumidores
- **Abstracción**: Los cambios de esquema no rompen dependencias externas
- **Versionamiento**: Puede mantener múltiples versiones de vistas durante migraciones
- **Rendimiento**: Puede incluir vistas indexadas o resultados materializados

### Estructura

**Esquema de Aplicación** (ej. vERP):
```sql
-- Crear esquema para aplicación ERP
CREATE SCHEMA vERP;

-- Crear usuario dedicado
CREATE USER dw_erp WITH PASSWORD = 'ContraseñaSegura123!';

-- Conceder acceso de solo lectura solo al esquema vERP
GRANT SELECT ON SCHEMA::vERP TO dw_erp;
DENY SELECT ON SCHEMA::Dim TO dw_erp;
DENY SELECT ON SCHEMA::Fact TO dw_erp;
DENY SELECT ON SCHEMA::Staging TO dw_erp;
```

**Vista de Aplicación**:
```sql
CREATE VIEW vERP.ProductionOrders
AS
SELECT
    -- Claves de Negocio
    po.CompanyId,
    po.ProductionOrderId,
    
    -- Dimensiones (nombres amigables para negocio)
    p.ProductCode,
    p.ProductName,
    w.WorkCenterCode,
    w.WorkCenterName,
    e.EmployeeName AS Operator,
    d.DateValue AS ProductionDate,
    
    -- Medidas
    po.PlannedQuantity,
    po.ActualQuantity,
    po.ScrapQuantity,
    po.ActualQuantity - po.ScrapQuantity AS GoodQuantity,
    
    -- Métricas Calculadas
    CASE 
        WHEN po.PlannedQuantity > 0 
        THEN (po.ActualQuantity * 100.0 / po.PlannedQuantity)
        ELSE 0 
    END AS EfficiencyPercent,
    
    -- Estado
    CASE 
        WHEN po.ActualQuantity >= po.PlannedQuantity THEN 'Completo'
        WHEN po.ActualQuantity > 0 THEN 'En Progreso'
        ELSE 'Planificado'
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

**Uso por Aplicación**:
```sql
-- La aplicación ERP se conecta como usuario dw_erp
-- Solo puede acceder al esquema vERP

SELECT 
    ProductionDate,
    ProductCode,
    SUM(ActualQuantity) AS TotalProduced
FROM vERP.ProductionOrders
WHERE ProductionDate >= '2026-05-01'
GROUP BY ProductionDate, ProductCode
ORDER BY ProductionDate, ProductCode;
```

## Patrón de Sincronización

### Sincronización de Dimensiones

El patrón de sincronización para dimensiones refleja el patrón Landing:

```sql
-- Paso 1: Crear staging temporal desde vista
SELECT * 
INTO #DimCustomerStaging
FROM Dim.CustomerView;

-- Paso 2: Generar claves sustitutas para nuevos registros
UPDATE s
SET CustomerKey = NEXT VALUE FOR Dim.CustomerSequence
FROM #DimCustomerStaging s
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer t
    WHERE t.CompanyId = s.CompanyId 
    AND t.CustomerId = s.CustomerId
);

-- Paso 3: MERGE en tabla de dimensión
MERGE Dim.Customer AS target
USING #DimCustomerStaging AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Escenario C: Actualizar registros cambiados (excluir miembros especiales)
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

-- Escenario A: Insertar nuevos registros
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

-- Escenario D: Eliminación suave de registros faltantes (excluir miembros especiales)
WHEN NOT MATCHED BY SOURCE 
    AND target.IsDeleted = 0 
    AND target.CustomerKey NOT IN (-1, -101) THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

**Diferencias Clave de Landing**:
1. **Generación de Clave Sustituta**: Los nuevos registros obtienen claves de la secuencia antes del MERGE
2. **Protección de Miembros Especiales**: MERGE excluye CustomerKey IN (-1, -101) para prevenir modificación
3. **Vista como Fuente**: #DimCustomerStaging poblado desde Dim.CustomerView

### Sincronización de Hechos

La sincronización de tablas de hechos sigue el mismo patrón:

```sql
-- Paso 1: Crear staging temporal desde vista
SELECT * 
INTO #FactSalesStaging
FROM Fact.SalesView;

-- Paso 2: MERGE en tabla de hechos
MERGE Fact.Sales AS target
USING #FactSalesStaging AS source
    ON target.CompanyId = source.CompanyId 
    AND target.OrderId = source.OrderId 
    AND target.LineNumber = source.LineNumber

-- Escenario C: Actualizar registros cambiados
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

-- Escenario A: Insertar nuevos registros
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

-- Escenario D: Eliminación suave de registros faltantes
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

### Orden de Sincronización

Ejecutar sincronizaciones en **orden de dependencia**:

```
1. Tablas Staging (si es necesario)
   ↓
2. Dimensiones (en orden de dependencia)
   ↓
3. Tablas Puente (después de dimensiones)
   ↓
4. Tablas de Hechos (después de dimensiones y puentes)
   ↓
5. Vistas de Aplicación (reflejan cambios automáticamente)
```

**Ejemplo**:
```sql
-- 1. Staging
EXEC Staging.UpdateCustomerRegion;

-- 2. Dimensiones (primero independientes, luego dependientes)
EXEC Dim.SynchronizeCustomerCategory;
EXEC Dim.SynchronizeCustomer;  -- depende de CustomerCategory
EXEC Dim.SynchronizeProduct;
EXEC Dim.SynchronizeEmployee;
EXEC Dim.SynchronizeDate;

-- 3. Tablas Puente
EXEC Bridge.SynchronizeProductCategory;

-- 4. Tablas de Hechos
EXEC Fact.SynchronizeSales;
```

## Beneficios y Justificación

### ¿Por Qué Modelado Dimensional?

**Esquema Normalizado Tradicional** (3NF):
```
Orders → Customers → CustomerTypes
      → OrderLines → Products → ProductCategories
                  → Suppliers → SupplierRegions
```
**Problemas para Analítica**:
- Joins multi-tabla complejos para preguntas simples
- Difícil de entender para usuarios de negocio
- Rendimiento pobre de consultas para agregaciones
- Difícil agregar nuevas medidas o atributos

**Modelo Dimensional** (Esquema en Estrella):
```
      Customer Dim ─┐
         Product Dim ┼─→ Sales Fact
            Date Dim ─┘
```
**Ventajas para Analítica**:
- ✅ Estructura intuitiva (refleja pensamiento de negocio)
- ✅ Consultas simples (joins mínimos)
- ✅ Rendimiento excelente (claves foráneas indexadas)
- ✅ Flexible (fácil agregar dimensiones/medidas)
- ✅ Consistente (dimensiones conformadas)

### ¿Por Qué Claves Sustitutas?

**Problemas de Clave Natural**:
- Cambian con el tiempo (reasignación de ID de cliente)
- Claves compuestas (CustomerID + CompanyID)
- Formatos diferentes entre fuentes (SAP vs Salesforce)
- Claves de cadena (rendimiento pobre)

**Beneficios de Clave Sustituta**:
- ✅ Nunca cambian (referencias de hechos estables)
- ✅ Entero único (rendimiento óptimo)
- ✅ Independiente de fuente (amigable para integración)
- ✅ Habilitan seguimiento de historial (SCD Tipo 2)
- ✅ Tablas de hechos más pequeñas (claves foráneas compactas)

### ¿Por Qué Miembros Especiales?

**Problemas de Clave Foránea NULL**:
```sql
-- Consulta sin miembros especiales
SELECT 
    ISNULL(c.CustomerName, '(Sin Cliente)') AS Customer,
    SUM(s.LineTotal) AS Sales
FROM Fact.Sales s
LEFT JOIN Dim.Customer c ON s.CustomerKey = c.CustomerKey
GROUP BY c.CustomerName;
```
**Problemas**:
- Outer joins en cada consulta (complejidad + rendimiento)
- Manejo de NULL en cada agregación
- Visualización inconsistente de valores NULL
- Sin restricción de integridad referencial

**Solución con Miembros Especiales**:
```sql
-- Consulta con miembros especiales
SELECT 
    c.CustomerName AS Customer,
    SUM(s.LineTotal) AS Sales
FROM Fact.Sales s
INNER JOIN Dim.Customer c ON s.CustomerKey = c.CustomerKey
GROUP BY c.CustomerName;
```
**Beneficios**:
- ✅ Inner joins (más simples, más rápidos)
- ✅ Integridad referencial forzada
- ✅ Representación NULL consistente ('(Vacío)', '(Desconocido)')
- ✅ Auditoría (contar Desconocidos para encontrar problemas de calidad)
- ✅ Todos los hechos se cargan (dimensiones faltantes no bloquean carga)

### ¿Por Qué Sincronización Basada en Vistas?

**Actualizaciones Directas de Tabla**:
```sql
-- Lógica de transformación embebida en procedimiento
UPDATE Dim.Customer SET Name = ...
```
**Problemas**:
- Lógica oculta en código procedimental
- Difícil probar transformaciones
- Difícil verificar "estado actual"
- No se puede consultar resultados de transformación antes de confirmar

**Enfoque Basado en Vistas**:
```sql
-- Lógica en vista (SQL declarativo)
CREATE VIEW Dim.CustomerView AS ...
-- Materializar en tabla
MERGE Dim.Customer ... USING Dim.CustomerView
```
**Beneficios**:
- ✅ Lógica de transformación visible (SELECT desde vista)
- ✅ Fácil de probar (comparar vista vs tabla)
- ✅ Patrón consistente (mismo que Landing)
- ✅ Puede consultar vista independientemente
- ✅ Clara separación de responsabilidades

### ¿Por Qué Esquemas de Aplicación?

**Acceso Directo a Tablas Núcleo**:
```sql
-- ERP consulta Fact.ProductionOrders directamente
GRANT SELECT ON Fact.ProductionOrders TO dw_erp;
```
**Problemas**:
- Riesgo de seguridad (aplicación ve todas las columnas/tablas)
- Acoplamiento ajustado (cambios de esquema rompen aplicaciones)
- Sin abstracción (no se puede cambiar modelo subyacente)
- Rendimiento (aplicaciones pueden escribir consultas ineficientes)

**Enfoque de Esquema de Aplicación**:
```sql
-- ERP consulta vERP.ProductionOrders (vista curada)
GRANT SELECT ON SCHEMA::vERP TO dw_erp;
```
**Beneficios**:
- ✅ Seguridad (principio de mínimo privilegio)
- ✅ Abstracción (puede refactorizar tablas subyacentes)
- ✅ Simplificación (lógica compleja oculta en vistas)
- ✅ Optimización (vistas indexadas si es necesario)
- ✅ Versionamiento (mantener vista antigua durante migración)

## Ejemplos

### Ejemplo 1: Implementación Completa de Dimensión

**Fuente Landing**:
```sql
-- Landing.ERP.Customer
CompanyId | CustomerId | CustomerName   | VAT      | CategoryId
----------|------------|----------------|----------|------------
1         | 100        | Acme Corp      | IT12345  | 1
1         | 101        | Beta LLC       | IT67890  | 2
```

**Enriquecimiento Staging**:
```sql
-- Staging.CustomerRegion (derivada de lógica código postal)
CREATE TABLE Staging.CustomerRegion
(
    CustomerId  INT,
    RegionId    INT,
    RegionName  NVARCHAR(50)
);
```

**Vista de Dimensión**:
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

**Tabla de Dimensión Después de Sincronización**:
```sql
-- Dim.Customer
CustomerKey | CompanyId | CustomerId | Name          | Category   | Region
------------|-----------|------------|---------------|------------|--------
-1          | -1        | -1         | (Vacío)       | (Vacío)    | (Vacío)
-101        | -101      | -101       | (Desconocido) | (Desconocido) | (Desconocido)
1           | 1         | 100        | Acme Corp     | Premium    | Norte
2           | 1         | 101        | Beta LLC      | Estándar   | Sur
```

### Ejemplo 2: Implementación Completa de Hechos

**Fuentes Landing**:
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

**Tablas de Dimensión**:
```sql
-- Dim.Customer
CustomerKey | CustomerId
------------|------------
-1          | -1         (Vacío)
-101        | -101       (Desconocido)
1           | 100        (Acme Corp - existe)
-- Cliente 999 no existe

-- Dim.Employee
EmployeeKey | EmployeeId
------------|------------
-1          | -1         (Vacío)
-101        | -101       (Desconocido)
10          | 5          (John Doe - existe)
```

**Vista de Hechos**:
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
    
    -- Búsquedas de dimensión con fallback a miembros especiales
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

**Tabla de Hechos Después de Sincronización**:
```sql
-- Fact.Sales
CompanyId | OrderId | LineNum | CustomerKey | SalesPersonKey | ProductKey | Quantity | LineTotal
----------|---------|---------|-------------|----------------|------------|----------|----------
1         | 1001    | 1       | 1           | 10             | 5          | 10       | 500.00
1         | 1002    | 1       | -101        | -1             | 6          | 5        | 500.00
          (Cliente 999 → Desconocido)  (NULL → Vacío)
```

**Consulta de Análisis**:
```sql
-- Ventas por Cliente (incluyendo Desconocido y Vacío)
SELECT 
    c.Name AS Customer,
    SUM(f.LineTotal) AS TotalSales,
    COUNT(*) AS OrderCount
FROM Fact.Sales f
INNER JOIN Dim.Customer c ON f.CustomerKey = c.CustomerKey
GROUP BY c.Name;

-- Resultado:
-- Customer        TotalSales  OrderCount
-- Acme Corp       500.00      1
-- (Desconocido)   500.00      1  ← Problema calidad datos: Cliente 999 faltante
```

### Ejemplo 3: Tabla Puente para Muchos-a-Muchos

**Escenario**: Los productos pueden pertenecer a múltiples categorías

**Datos Landing**:
```sql
-- Landing.ERP.ProductCategoryMapping
ProductId | CategoryId
----------|------------
200       | 1          (Electrónica)
200       | 3          (Accesorios)
201       | 1          (Electrónica)
```

**Tabla Puente**:
```sql
-- Bridge.ProductCategory
ProductKey | CategoryKey | AllocationPercent
-----------|-------------|-------------------
5          | 10          | 50.00
5          | 12          | 50.00
6          | 10          | 100.00
```

**Consulta con Puente**:
```sql
-- Ventas por Categoría (con asignación)
SELECT 
    cat.CategoryName,
    SUM(f.LineTotal * b.AllocationPercent / 100) AS AllocatedSales
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category cat ON b.CategoryKey = cat.CategoryKey
GROUP BY cat.CategoryName;

-- Resultado:
-- CategoryName      AllocatedSales
-- Electrónica       750.00  (500 * 50% + 500 * 100%)
-- Accesorios        250.00  (500 * 50%)
```

## Mejores Prácticas

### 1. Diseño de Dimensiones

**Mantener Dimensiones Desnormalizadas**:
```sql
-- Bien: Desnormalizado (esquema en estrella)
Dim.Customer: CustomerKey, Name, Category, Region, Segment

-- Mal: Normalizado (esquema copo de nieve)
Dim.Customer: CustomerKey, Name, CategoryKey
Dim.CustomerCategory: CategoryKey, CategoryName, RegionKey
Dim.Region: RegionKey, RegionName
```
**Por Qué**: Los esquemas copo de nieve requieren más joins, reduciendo rendimiento de consultas y facilidad de uso.

**Usar Etiquetas de Miembros Especiales Significativas**:
```sql
-- Bien: Etiquetado claro
Name = '(Vacío)'  o '(No Aplicable)'
Name = '(Desconocido)' o '(Referencia Faltante)'

-- Mal: Ambiguo
Name = 'N/A'
Name = 'NULL'
Name = ''
```

**Agregar Atributos de Conteo de Filas para Agregación**:
```sql
-- Agregar a tabla de dimensión para conteo fácil
RowCount INT NOT NULL DEFAULT 1

-- Habilita conteos precisos en reportes
SELECT Customer, SUM(RowCount) AS TransactionCount
FROM Fact.Sales f
INNER JOIN Dim.Customer c ON f.CustomerKey = c.CustomerKey
GROUP BY Customer;
```

### 2. Diseño de Tablas de Hechos

**Declarar Granularidad Explícitamente**:
```sql
-- Documentar granularidad en comentarios
-- GRANULARIDAD: Una fila por línea de pedido (CompanyId, OrderId, LineNumber)
CREATE TABLE Fact.Sales (...);

-- Mal: Granularidad ambigua
-- ¿Podría ser por pedido? ¿Por línea? ¿Por cliente?
```

**Incluir Solo Medidas Aditivas en Agregaciones**:
```sql
-- Bien: Sumar medidas aditivas
SELECT Customer, SUM(LineTotal) AS TotalSales FROM ...

-- Mal: Sumar medidas no-aditivas
SELECT Customer, SUM(UnitPrice) AS ??? FROM ...  -- No tiene sentido

-- Usar AVG para medidas no-aditivas en su lugar
SELECT Customer, AVG(UnitPrice) AS AvgPrice FROM ...
```

**Preferir Claves Sustitutas Incluso en Hechos**:
```sql
-- Considerar agregar clave sustituta incluso a hechos (opcional)
SalesKey BIGINT IDENTITY(1,1) PRIMARY KEY

-- Beneficios:
-- - Identificador de fila simple para referencias
-- - Puede mejorar rendimiento para algunas consultas
-- - Útil para rastrear correcciones/ajustes
```

### 3. Estrategias de Indexación

**Patrón de Índices Estándar para Dimensiones**:
```sql
-- Clave primaria sustituta (clustered)
PRIMARY KEY CLUSTERED (CustomerKey)

-- Índice único en clave natural
UNIQUE NONCLUSTERED (CompanyId, CustomerId)

-- Índice en hash para detección de cambios
NONCLUSTERED (ChangeHashKey)
```

**Patrón de Índices Estándar para Hechos**:
```sql
-- Clave primaria en claves naturales (clustered)
PRIMARY KEY CLUSTERED (CompanyId, OrderId, LineNumber)

-- Índices non-clustered en cada clave foránea dimensional
NONCLUSTERED (CustomerKey) INCLUDE (LineTotal, Quantity)
NONCLUSTERED (ProductKey) INCLUDE (LineTotal, Quantity)
NONCLUSTERED (OrderDateKey) INCLUDE (LineTotal, Quantity)

-- Índices para patrones de consulta comunes
NONCLUSTERED (OrderDateKey, CustomerKey) INCLUDE (LineTotal)
```

### 4. Gestión de Miembros Especiales

**Nunca Modificar Miembros Especiales**:
```sql
-- Siempre excluir miembros especiales de actualizaciones
MERGE Dim.Customer AS target
...
WHEN MATCHED 
    AND target.CustomerKey NOT IN (-1, -101)  -- CRÍTICO
    AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET ...
```

**Monitorear Miembros Desconocidos**:
```sql
-- Crear vista de monitoreo de calidad de datos
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

### 5. Pruebas y Validación

**Validar Integridad Referencial**:
```sql
-- Verificar que todos los hechos tengan claves foráneas válidas
SELECT 'Claves Customer Huérfanas' AS Problem, COUNT(*) AS Count
FROM Fact.Sales f
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer c WHERE c.CustomerKey = f.CustomerKey
);
```

**Comparar Vista vs Tabla**:
```sql
-- Verificar que la tabla refleje la vista
SELECT 'Solo en Vista' AS Source, COUNT(*) AS Count
FROM Dim.CustomerView v
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer t 
    WHERE t.CompanyId = v.CompanyId AND t.CustomerId = v.CustomerId
)
UNION ALL
SELECT 'Solo en Tabla' AS Source, COUNT(*) AS Count
FROM Dim.Customer t
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.CustomerView v 
    WHERE v.CompanyId = t.CompanyId AND v.CustomerId = t.CustomerId
)
AND t.CustomerKey NOT IN (-1, -101);  -- Excluir miembros especiales
```

---

## Resumen

Este patrón de diseño de Data Warehouse proporciona:

✅ **Intuitividad**: El modelo dimensional refleja pensamiento de negocio  
✅ **Rendimiento**: Esquema en estrella optimizado para consultas analíticas  
✅ **Integridad**: Miembros especiales garantizan integridad referencial  
✅ **Flexibilidad**: Transformaciones basadas en vistas adaptables  
✅ **Seguridad**: Esquemas de aplicación aíslan acceso  
✅ **Mantenibilidad**: Patrones consistentes y estructura clara  

Siguiendo estos principios, creas un data warehouse robusto que transforma datos crudos en insights analíticos mientras mantiene integridad, rendimiento y facilidad de uso.

---

**Versión del Documento**: 1.0  
**Última Actualización**: 20 de mayo de 2026  
**Stack Tecnológico**: Microsoft SQL Server 2016+, Metodología Kimball
