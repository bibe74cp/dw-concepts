# Flujo de Sincronización Landing Zone - Documentación Técnica

## Tabla de Contenidos
- [Visión General](#visión-general)
- [Arquitectura](#arquitectura)
- [Estructura de Paquete SSIS](#estructura-de-paquete-ssis)
- [Pasos de Sincronización](#pasos-de-sincronización)
- [Patrones de Implementación](#patrones-de-implementación)
- [Manejo de Errores](#manejo-de-errores)
- [Optimización de Rendimiento](#optimización-de-rendimiento)
- [Ejemplos](#ejemplos)
- [Mejores Prácticas](#mejores-prácticas)
- [Monitoreo y Logging](#monitoreo-y-logging)

## Visión General

Este documento describe la implementación técnica del **flujo de sincronización** que carga datos desde sistemas fuente hacia la zona Landing usando **SQL Server Integration Services (SSIS)**. Cada tabla Landing tiene un paquete SSIS dedicado que implementa un patrón consistente y repetible para detectar y aplicar cambios.

### Propósito

El flujo de sincronización asegura que:
- Las tablas Landing sean réplicas fieles de las tablas fuente
- Los cambios se detecten eficientemente usando comparación basada en hash
- Todos los cambios se rastreen con metadatos temporales
- Los registros eliminados se manejen con patrón de eliminación suave
- El proceso sea idempotente y pueda repetirse de manera segura

### Principios de Diseño

1. **Paquete-por-Tabla**: Cada tabla Landing tiene su propio paquete SSIS
2. **CDC Basado en Hash**: Cambios detectados comparando hashes SHA256
3. **Merge de Tres Vías**: Manejar inserciones, actualizaciones y eliminaciones en una sola ejecución
4. **Idempotente**: Ejecutar el mismo paquete múltiples veces produce el mismo resultado
5. **Atómico**: Cada sincronización es una sola transacción
6. **Auditable**: Logging completo de todas las operaciones

## Arquitectura

### Flujo de Alto Nivel

```
┌─────────────────────────────────────────────────────────────────┐
│                      Sistema Fuente                             │
│                   (ERP, Salesforce, MES)                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Paso 1: Extracción & Hash  │
              │   SELECT con HASHBYTES()     │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Paso 2: Split Condicional  │
              │   Enrutamiento basado en     │
              │   existencia y comparación   │
              └──────────────┬───────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌────────┐         ┌────────┐         ┌────────┐
    │ INSERT │         │ UPDATE │         │  SKIP  │
    │ Nuevo  │         │Cambiad │         │Sin Camb│
    └────────┘         └────────┘         └────────┘
         │                   │                   │
         └───────────────────┴───────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Paso 3: Eliminación Suave  │
              │   Marcar faltantes como      │
              │   eliminados                 │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Logging de Auditoría       │
              │   Registrar métricas & estado│
              └──────────────────────────────┘
```

### Componentes de Flujo de Datos

```
Fuente → Data Flow Task → Destino
         │
         ├─ OLE DB Source (Extracción con Hash)
         ├─ Lookup Transformation (Verificar Existencia)
         ├─ Conditional Split (Enrutar por Hash)
         ├─ OLE DB Command (Actualizar Cambiados)
         ├─ OLE DB Destination (Insertar Nuevos)
         └─ Execute SQL Task (Eliminación Suave)
```

## Estructura de Paquete SSIS

### Variables de Paquete

Cada paquete SSIS define las siguientes variables:

| Variable | Tipo | Propósito | Ejemplo |
|----------|------|---------|---------|
| `SourceServer` | String | Servidor de base de datos fuente | `ERP_PROD_SERVER` |
| `SourceDatabase` | String | Nombre de base de datos fuente | `ERP_Production` |
| `SourceSchema` | String | Nombre de esquema fuente | `dbo` |
| `SourceTable` | String | Nombre de tabla fuente | `Customer` |
| `LandingSchema` | String | Nombre de esquema landing | `ERP` |
| `LandingTable` | String | Nombre de tabla landing | `Customer` |
| `HashColumns` | String | Columnas para hash | `CustomerName,VAT` |
| `PKColumns` | String | Columnas de clave primaria | `CompanyId,CustomerId` |
| `RecordsInserted` | Int32 | Conteo de registros insertados | 0 |
| `RecordsUpdated` | Int32 | Conteo de registros actualizados | 0 |
| `RecordsDeleted` | Int32 | Conteo de registros eliminados | 0 |
| `ExecutionStart` | DateTime | Hora de inicio del paquete | `2026-05-21 10:00:00` |

### Connection Managers

1. **Source Connection**: Conexión OLE DB al sistema fuente (solo lectura)
2. **Landing Connection**: Conexión OLE DB a base de datos Landing (lectura-escritura)
3. **Audit Connection**: Conexión OLE DB para logging (opcional, puede usar Landing)

### Flujo de Control del Paquete

```
┌─────────────────────────────────────────────────────────────┐
│  Flujo de Control                                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. [Establecer Variables] (Script Task)                   │
│     ↓                                                       │
│  2. [Truncar Staging] (Execute SQL Task)                   │
│     ↓                                                       │
│  3. [Extraer & Cargar] (Data Flow Task) ──────┐            │
│     ↓                                          │            │
│  4. [Eliminación Suave Faltantes] (Execute SQL Task)│      │
│     ↓                                          │            │
│  5. [Log Ejecución] (Execute SQL Task)         │            │
│     ↓                                          │            │
│  6. [Limpieza Staging] (Execute SQL Task)      │            │
│                                                │            │
│  En Error: [Log Error] (Execute SQL Task) ←───┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Pasos de Sincronización

### Paso 1: Extracción desde Fuente con Cálculo de Hash

**Propósito**: Leer datos fuente y calcular hash para detección de cambios

**Implementación**: Componente OLE DB Source con consulta SQL dinámica

**Patrón de Consulta SQL**:
```sql
-- Consulta dinámica generada desde variables de paquete
SELECT 
    -- Columnas de Clave Primaria
    CompanyId,
    CustomerId,
    
    -- Hash Calculado (ChangeHashKey)
    HASHBYTES('SHA2_256', 
        CONCAT(
            ISNULL(CustomerName, ''), '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey,
    
    -- Columnas de Negocio
    CustomerName,
    VAT

FROM [ERP].[dbo].[Customer]
WHERE 1=1  -- Opcional: agregar filtro incremental para tablas muy grandes
```

**Puntos Clave**:
- El hash se calcula en la fuente para minimizar transferencia de datos
- Usar `ISNULL()` para manejar valores NULL consistentemente
- Usar delimitador (`|`) para evitar colisiones de hash
- Convertir todos los tipos de datos a cadena antes del hash
- Solo incluir columnas que existen en tabla Landing

**Consideración de Rendimiento**:
```sql
-- Para tablas muy grandes (100M+ filas), agregar filtro
-- Ejemplo: carga incremental basada en ModifiedDate
WHERE ModifiedDate >= DATEADD(DAY, -7, GETDATE())

-- O usar change tracking si está disponible
WHERE CHANGE_TRACKING_VERSION >= @LastSyncVersion
```

### Paso 2: Split Condicional y Enrutamiento

**Propósito**: Enrutar registros a destinos apropiados basándose en existencia y detección de cambios

**Implementación**: Componentes de Data Flow

#### 2.1 Lookup Transformation

**Configuración**:
- **Tabla Lookup**: `Landing.ERP.Customer`
- **Columnas de Join**: Columnas de clave primaria (`CompanyId`, `CustomerId`)
- **Columnas Devueltas**: `ChangeHashKey`, `IsDeleted`
- **Salida Sin Coincidencia**: Nuevos registros (enrutar a INSERT)
- **Salida Con Coincidencia**: Registros existentes (enrutar a Conditional Split)

**Modo de Caché**:
- **Full Cache**: Para dimensiones pequeñas (< 1M filas) - más rápido
- **Partial Cache**: Para tablas medianas (1M-10M filas) - balanceado
- **No Cache**: Para tablas muy grandes (> 10M filas) - eficiente en memoria

**Consulta Lookup**:
```sql
SELECT 
    CompanyId,
    CustomerId,
    ChangeHashKey,
    IsDeleted
FROM [Landing].[ERP].[Customer]
```

#### 2.2 Conditional Split Transformation

**Propósito**: Separar registros emparejados en cambiados vs sin cambiar

**Condiciones de Split**:

| Nombre de Salida | Condición | Acción |
|-------------|-----------|--------|
| `Changed` | `Source.ChangeHashKey != Landing.ChangeHashKey` | Enrutar a UPDATE |
| `Unchanged` | `Source.ChangeHashKey == Landing.ChangeHashKey` | Sin acción (ignorar) |

**Sintaxis de Expresión** (SSIS):
```
-- Salida de Registros Cambiados
[Source_ChangeHashKey] != [Landing_ChangeHashKey]

-- Registros Sin Cambiar (Salida Predeterminada)
-- No se necesita condición - captura todos los registros sin cambios
```

#### 2.3 Enrutamiento de Flujo de Datos

**Tres Rutas**:

1. **Salida Sin Coincidencia desde Lookup** → OLE DB Destination (INSERT)
2. **Salida Cambiados desde Conditional Split** → OLE DB Command (UPDATE)
3. **Salida Sin Cambiar desde Conditional Split** → Row Count (solo métricas, sin acción)

### Paso 2.4: INSERT Nuevos Registros

**Componente**: OLE DB Destination

**Tabla de Destino**: `[Landing].[ERP].[Customer]`

**Mapeo de Columnas**:
```
Columna Fuente         → Columna Destino
─────────────────────────────────────────────
CompanyId              → CompanyId
CustomerId             → CustomerId
ChangeHashKey          → ChangeHashKey
CustomerName           → CustomerName
VAT                    → VAT
CURRENT_TIMESTAMP      → InsertDatetime
CURRENT_TIMESTAMP      → UpdateDatetime
0 (constante)          → IsDeleted
```

**Derived Column Transformation** (antes de INSERT):
```
Nombre Columna    Expresión                   Tipo de Datos
─────────────────────────────────────────────────────────────
InsertDatetime    GETDATE()                   DT_DBTIMESTAMP
UpdateDatetime    GETDATE()                   DT_DBTIMESTAMP
IsDeleted         (DT_BOOL)0                  DT_BOOL
```

**Consulta Insert** (generada por destino):
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

### Paso 2.5: UPDATE Registros Cambiados

**Componente**: OLE DB Command

**Consulta Update**:
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

**Mapeo de Parámetros** (el orden importa):
```
Parámetro  Columna Fuente     Tipo
────────────────────────────────────
Param_0    ChangeHashKey      BINARY(32)
Param_1    CustomerName       NVARCHAR(100)
Param_2    VAT                NVARCHAR(20)
Param_3    CompanyId          INT
Param_4    CustomerId         INT
```

**Notas Importantes**:
- `InsertDatetime` NO se actualiza (preserva tiempo de inserción original)
- `UpdateDatetime` se establece a `CURRENT_TIMESTAMP`
- `IsDeleted` NO se modifica (preserva estado de eliminación si existe)
- TODAS las columnas de negocio se actualizan (incluso si solo una cambió)

**Advertencia de Rendimiento**:
- OLE DB Command ejecuta UPDATE fila por fila (lento para actualizaciones grandes)
- Para actualizaciones masivas, considerar enfoque de tabla staging (ver Optimización de Rendimiento)

### Paso 3: Eliminación Suave de Registros Faltantes

**Propósito**: Marcar registros que existen en Landing pero no en fuente como eliminados

**Implementación**: Execute SQL Task

**Sentencia SQL**:
```sql
-- Eliminación suave de registros no presentes en extracción fuente actual
UPDATE t
SET 
    UpdateDatetime = CURRENT_TIMESTAMP,
    IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0  -- Solo procesar registros activos
    AND NOT EXISTS (
        SELECT 1 
        FROM #Staging s  -- Tabla staging poblada durante data flow
        WHERE s.CompanyId = t.CompanyId 
            AND s.CustomerId = t.CustomerId
    );

-- Devolver conteo para logging
SELECT @@ROWCOUNT AS DeletedCount;
```

**Enfoque Alternativo** (sin staging):
```sql
-- Usar MERGE para las tres operaciones en una sentencia
MERGE [Landing].[ERP].[Customer] AS target
USING (
    -- Consulta fuente del Paso 1
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

-- UPDATE registros cambiados
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- INSERT nuevos registros
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

-- ELIMINACIÓN SUAVE de registros faltantes
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

## Patrones de Implementación

### Patrón 1: Data Flow con Tabla Staging

**Patrón Más Común** - Flexible y eficiente para la mayoría de escenarios

**Pasos**:

1. **Crear/Truncar Tabla Staging**:
```sql
-- Execute SQL Task: Truncar Staging
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

2. **Data Flow: Extracción → Staging**:
   - OLE DB Source: Consulta con cálculo de hash
   - OLE DB Destination: `#Staging_ERP_Customer`

3. **Execute SQL: Merge Staging → Landing**:
```sql
-- Realizar merge de tres vías
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

**Ventajas**:
- Todas las operaciones en un solo MERGE (atómico)
- Mejor rendimiento para actualizaciones grandes
- Depuración más simple (tabla staging puede inspeccionarse)
- Recuperación de errores más fácil

**Desventajas**:
- Requiere almacenamiento adicional (tabla staging)
- Proceso de dos pasos (extraer, luego merge)

### Patrón 2: Data Flow Directo (Sin Staging)

**Más rápido para tablas pequeñas** - Elimina staging intermedio

**Pasos**:

1. **Data Flow con Enrutamiento Condicional**:
   - OLE DB Source con cálculo de hash
   - Lookup Transformation (emparejar en PK)
   - Conditional Split (comparar hashes)
   - OLE DB Destination (INSERT nuevos)
   - OLE DB Command (UPDATE cambiados)

2. **Execute SQL: Eliminación Suave**:
```sql
-- Marcar como eliminados registros no vistos en esta ejecución
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0
    AND t.UpdateDatetime < ?  -- Hora inicio paquete
    AND NOT EXISTS (
        SELECT 1 FROM [ERP].[dbo].[Customer] s
        WHERE s.CompanyId = t.CompanyId 
        AND s.CustomerId = t.CustomerId
    );
```

**Ventajas**:
- Menos pasos (más rápido para tablas pequeñas)
- No se requiere almacenamiento staging
- Un solo paso a través de los datos

**Desventajas**:
- OLE DB Command es fila por fila (lento para actualizaciones grandes)
- Depuración más difícil (sin estado intermedio)
- Eliminación suave requiere consulta separada a fuente

### Patrón 3: Híbrido (Staging + Flujo Optimizado)

**Mejor rendimiento para tablas grandes** - Combina beneficios de ambos

**Pasos**:

1. **Crear Staging con Índices**:
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
   - Fast Load habilitado
   - Logging mínimo
   - Sin restricciones durante insert

3. **T-SQL Merge** (como en Patrón 1)

4. **Eliminación Suave Indexada**:
```sql
-- Anti-join eficiente con staging indexado
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
    LEFT JOIN #Staging_ERP_Customer s
        ON t.CompanyId = s.CompanyId 
        AND t.CustomerId = s.CustomerId
WHERE t.IsDeleted = 0
    AND s.CompanyId IS NULL;
```

## Manejo de Errores

### Gestión de Transacciones

**Transacción a Nivel de Paquete**:
```
Propiedades del Paquete:
- TransactionOption: Required
- IsolationLevel: ReadCommitted
```

Todas las tareas dentro del paquete participan en una sola transacción:
- Si alguna tarea falla, todo el paquete hace rollback
- La tabla Landing permanece en estado consistente
- Se puede reintentar el paquete completo de manera segura

**Manejo de Errores a Nivel de Tarea**:
```
Cada Tarea:
- En Error → Execute SQL Task (Log Error)
- En Éxito → Siguiente Tarea
```

### Logging de Errores

**Tabla de Errores de Auditoría**:
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
    
    -- Variables del Sistema SSIS
    ExecutionID         UNIQUEIDENTIFIER NULL,
    MachineName         NVARCHAR(128) NULL,
    UserName            NVARCHAR(128) NULL
);
```

**SQL de Logging de Error** (Execute SQL Task en error):
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

### Lógica de Reintento

**Configuración de Paquete**:
- **Max Concurrent Executables**: 1 (prevenir ejecuciones concurrentes)
- **Checkpoint Enabled**: False (reintento de paquete completo, no a nivel de tarea)
- **Force Execution Result**: False (permitir finalización natural)

**Configuración de SQL Agent Job**:
- **Intentos de Reintento**: 3
- **Intervalo de Reintento**: 5 minutos
- **En Fallo**: Notificación por correo electrónico

## Optimización de Rendimiento

### Técnicas de Optimización

#### 1. Optimización de Consulta Fuente

**Hints de Índice**:
```sql
-- Usar índice apropiado para escaneo de fuente
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer] WITH (INDEX(IX_ModifiedDate))
WHERE ModifiedDate >= @LastSync
```

**Procesamiento Paralelo**:
```sql
-- Habilitar ejecución de consulta paralela para tablas grandes
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer]
OPTION (MAXDOP 4)
```

#### 2. Ajuste de Data Flow SSIS

**Configuración de Buffer**:
```
Propiedades de Data Flow:
- DefaultBufferMaxRows: 10000 (predeterminado)
- DefaultBufferSize: 10485760 (10MB predeterminado)
- EngineThreads: 10 (o conteo de CPU)
```

**Configuración de OLE DB Destination**:
```
Opciones de Fast Load:
- Table Lock: True
- Check Constraints: False
- Keep Identity: False
- Keep Nulls: True
- Rows per Batch: 100000
- Maximum Insert Commit Size: 100000
```

**Lookup Transformation**:
```
Configuración de Caché (para Full Cache):
- Enable Memory Restriction: True
- Cache Size (MB): 256 (ajustar según tamaño de dimensión)
- Enable Disk Cache: True (para lookups grandes)
```

#### 3. Optimización de Tabla Staging

**Usar Tabla Heap para Staging**:
```sql
-- Sin índice clustered durante insert (más rápido)
CREATE TABLE #Staging_ERP_Customer
(
    CompanyId       INT NOT NULL,
    CustomerId      INT NOT NULL,
    ChangeHashKey   BINARY(32) NOT NULL,
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20)
);

-- Agregar índices DESPUÉS del insert
CREATE CLUSTERED INDEX CIX_PK 
    ON #Staging_ERP_Customer (CompanyId, CustomerId);

CREATE NONCLUSTERED INDEX IX_Hash 
    ON #Staging_ERP_Customer (ChangeHashKey);
```

#### 4. Minimizar Bloqueo

**Read Uncommitted para Fuente**:
```sql
-- Las consultas fuente no necesitan bloqueos (solo lectura)
SELECT ...
FROM [ERP].[dbo].[Customer] WITH (NOLOCK)
WHERE ...
```

**Commits por Lotes para Landing**:
```sql
-- Commit cada N filas para liberar bloqueos
MERGE [Landing].[ERP].[Customer] AS target
USING #Staging AS source
    ON ...
WHEN MATCHED THEN UPDATE ...
WHEN NOT MATCHED THEN INSERT ...
OPTION (OPTIMIZE FOR (@BatchSize = 50000));
```

## Ejemplos

### Ejemplo 1: Carga de Dimensión Simple (Customer)

**Tabla Fuente**:
```sql
-- [ERP].[dbo].[Customer]
CompanyId | CustomerId | CustomerName     | VAT      | CreditLimit
----------|------------|------------------|----------|------------
1         | 100        | Acme Corp        | IT12345  | 50000.00
1         | 101        | Beta LLC         | IT67890  | 25000.00
1         | 102        | Gamma Solutions  | IT11111  | 100000.00
```

**Tabla Landing**:
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

**Paquete SSIS: Load_ERP_Customer**

**Paso 1: Consulta de Extracción**:
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

**Resultado**:
```
CompanyId | CustomerId | ChangeHashKey  | CustomerName     | VAT
----------|------------|----------------|------------------|--------
1         | 100        | 0xA1B2C3...    | Acme Corp        | IT12345
1         | 101        | 0xD4E5F6...    | Beta LLC         | IT67890
1         | 102        | 0x789ABC...    | Gamma Solutions  | IT11111
```

**Paso 2: Data Flow**

Asumir que la tabla Landing actualmente tiene:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName  | VAT     | IsDeleted
----------|------------|---------------|---------------|---------|----------
1         | 100        | 0xA1B2C3...   | Acme Corp     | IT12345 | 0
1         | 101        | 0xOLDHASH..   | Beta LLC      | IT67890 | 0
1         | 103        | 0x999888...   | Delta Inc     | IT55555 | 0
```

**Resultados de Lookup**:
- Customer 100: **Emparejado** (existe en Landing)
- Customer 101: **Emparejado** (existe en Landing)
- Customer 102: **Sin Coincidencia** (nuevo registro)
- Customer 103: (en Landing pero no en fuente - será eliminado soft)

**Conditional Split**:
- Customer 100: Hash coincide → **Sin Cambiar** (sin acción)
- Customer 101: Hash difiere → **Cambiado** (enrutar a UPDATE)
- Customer 102: Sin coincidencia → **Nuevo** (enrutar a INSERT)

**Acciones**:

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

**Paso 3: Eliminación Suave**:
```sql
UPDATE [Landing].[ERP].[Customer]
SET 
    UpdateDatetime = '2026-05-21 10:15:00',
    IsDeleted = 1
WHERE CompanyId = 1 AND CustomerId = 103
    AND IsDeleted = 0
```

**Estado Final de Tabla Landing**:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName     | VAT     | IsDeleted | UpdateDatetime
----------|------------|---------------|------------------|---------|-----------|----------------
1         | 100        | 0xA1B2C3...   | Acme Corp        | IT12345 | 0         | (sin cambio)
1         | 101        | 0xD4E5F6...   | Beta LLC         | IT67890 | 0         | 2026-05-21 10:15
1         | 102        | 0x789ABC...   | Gamma Solutions  | IT11111 | 0         | 2026-05-21 10:15
1         | 103        | 0x999888...   | Delta Inc        | IT55555 | 1         | 2026-05-21 10:15
```

**Métricas**:
- Registros Insertados: 1 (Customer 102)
- Registros Actualizados: 1 (Customer 101)
- Registros Eliminados: 1 (Customer 103)
- Registros Sin Cambiar: 1 (Customer 100)

## Mejores Prácticas

### 1. Diseño de Paquete

**Convención de Nomenclatura**:
```
Patrón: Load_{Esquema}_{Tabla}.dtsx
Ejemplos:
- Load_ERP_Customer.dtsx
- Load_SALESFORCE_Account.dtsx
- Load_MES_ProductionOrder.dtsx
```

**Parametrización**:
```
Usar parámetros de paquete para:
- Cadena de conexión fuente
- Cadena de conexión landing
- Criterios de filtro (rangos de fechas)
- Tamaño de lote

Evitar hardcoding:
- Nombres de servidor
- Nombres de base de datos
- Credenciales
```

**Control de Versiones**:
- Almacenar paquetes en control de fuente (Git, TFS)
- Usar Project Deployment Model (SSISDB)
- Etiquetar releases con números de versión
- Documentar cambios en anotaciones de paquete

### 2. Cálculo de Hash

**Orden Consistente**:
```sql
-- Siempre usar mismo orden de columnas en hash
CONCAT(Col1, '|', Col2, '|', Col3)  -- Bien

-- No cambiar orden entre cargas
CONCAT(Col2, '|', Col1, '|', Col3)  -- Mal (produce hash diferente)
```

**Manejo de Tipo de Datos**:
```sql
-- Convertir todos los tipos a cadena con formato fijo
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

**Excluir Columnas Volátiles**:
```sql
-- No incluir en hash:
-- - Timestamps de modificación (causaría actualizaciones continuas)
-- - Columnas de auditoría (CreatedBy, ModifiedBy)
-- - Valores calculados que cambian frecuentemente
```

### 3. Monitoreo y Logging

**Vista de Resumen de Ejecución de Auditoría**:
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

**Alertas de Calidad de Datos**:
```sql
-- Alertar si demasiados registros desconocidos/eliminados
IF (SELECT COUNT(*) FROM [Landing].[ERP].[Customer] WHERE IsDeleted = 1) > 1000
BEGIN
    RAISERROR('Número anormalmente alto de eliminaciones detectadas', 16, 1);
END
```

### 4. Gestión de Esquema

**Cambios de Esquema**:
```
1. Agregar columna a tabla Landing
2. Actualizar consulta de extracción (incluir nueva columna)
3. Actualizar cálculo de hash (incluir nueva columna)
4. Actualizar mapeos de paquete SSIS
5. Probar con dataset pequeño
6. Desplegar y monitorear
```

**Versionamiento de Hash**:
```sql
-- Incluir versión en hash para cambios de esquema
HASHBYTES('SHA2_256', 
    CONCAT(
        'v2|',  -- Prefijo de versión
        Col1, '|',
        Col2, '|',
        ColNueva  -- Nueva columna
    )
)
```

## Monitoreo y Logging

### Tabla de Log ETL

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
    
    -- Métricas de Rendimiento
    SourceRowCount      INT NULL,
    LandingRowCount     INT NULL,
    DurationSeconds     AS DATEDIFF(SECOND, ExecutionStart, ExecutionEnd),
    
    -- Metadatos SSIS
    ExecutionID         UNIQUEIDENTIFIER NULL,
    ServerName          NVARCHAR(128) NULL,
    UserName            NVARCHAR(128) NULL
);

-- Índice para consultas comunes
CREATE INDEX IX_PackageExecution 
    ON [audit].[ETLLog] (PackageName, ExecutionStart DESC);
```

### Panel de Monitoreo

**Vista de Estado Actual**:
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
    
    -- Indicador de salud
    CASE
        WHEN DATEDIFF(HOUR, l.LastLoadTime, GETDATE()) > 24 
            THEN 'OBSOLETO'
        WHEN l.LastStatus = 'Failed' 
            THEN 'ERROR'
        WHEN DATEDIFF(HOUR, l.LastLoadTime, GETDATE()) > 6 
            THEN 'ADVERTENCIA'
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

## Resumen

Este patrón de sincronización proporciona:

✅ **Consistencia**: Réplica fiel de datos fuente en zona Landing  
✅ **Eficiencia**: Detección de cambios basada en hash minimiza overhead  
✅ **Confiabilidad**: Patrón idempotente permite reintentos seguros  
✅ **Trazabilidad**: Logging completo de todas las operaciones  
✅ **Mantenibilidad**: Estructura de paquete consistente entre todas las tablas  
✅ **Rendimiento**: Optimizaciones para tablas de todos los tamaños  

Siguiendo estos patrones, creas un proceso ETL robusto que carga eficientemente datos desde sistemas fuente manteniendo integridad de datos y rastro de auditoría completo.

---

**Versión del Documento**: 1.0  
**Última Actualización**: 21 de mayo de 2026  
**Stack Tecnológico**: Microsoft SQL Server 2016+, SSIS 2016+, BIML 5.0+
