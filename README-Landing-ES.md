# Data Warehouse Landing Zone - Patrón de Diseño

## Tabla de Contenidos
- [Visión General](#visión-general)
- [Arquitectura](#arquitectura)
- [Conceptos Clave](#conceptos-clave)
- [Diseño de Esquema](#diseño-de-esquema)
- [Estructura de Tablas](#estructura-de-tablas)
- [Patrón de Actualización](#patrón-de-actualización)
- [Beneficios y Justificación](#beneficios-y-justificación)
- [Ejemplos](#ejemplos)
- [Mejores Prácticas](#mejores-prácticas)

## Visión General

La **Landing Zone** (también conocida como **Área de Staging** o **Capa de Datos Crudos**) es la primera capa en una arquitectura de data warehouse donde los datos de varios sistemas fuente se cargan inicialmente. Este documento describe un patrón probado para diseñar y gestionar la Landing zone usando Microsoft SQL Server.

### Propósito de la Landing Zone

La Landing zone cumple varias funciones críticas:
- **Desacoplamiento**: Aísla el data warehouse de los sistemas fuente, reduciendo dependencias y carga en bases de datos operacionales
- **Almacenamiento Temporal**: Proporciona un snapshot de datos fuente en puntos específicos en el tiempo
- **Detección de Cambios**: Rastrea qué datos han cambiado desde la última carga
- **Calidad de Datos**: Actúa como punto de control antes de que los datos se muevan a capas más refinadas
- **Auditabilidad**: Mantiene un registro de cuándo llegaron los datos y cómo cambiaron

## Arquitectura

### Estructura de la Base de Datos

```
Base de Datos Landing
├── audit (esquema)
│   ├── Tables (tablas de log para operaciones ETL)
│   ├── Views (vistas de monitoreo y reportes)
│   └── Stored Procedures (procedimientos de logging y utilidad)
├── ERP (esquema)
│   ├── Customer
│   ├── Order
│   └── ... (otras tablas ERP)
├── SALESFORCE (esquema)
│   ├── Account
│   ├── Opportunity
│   └── ... (otros objetos Salesforce)
├── MES (esquema)
│   ├── ProductionOrder
│   ├── WorkCenter
│   └── ... (otras tablas MES)
└── ... (esquemas fuente adicionales)
```

### Principios de Diseño

1. **Base de Datos Landing Única**: Todos los sistemas fuente depositan sus datos en una base de datos común
2. **Esquema-por-Fuente**: Cada fuente de datos tiene su propio esquema, nombrado en MAYÚSCULAS
3. **Aislamiento de Esquemas**: Los esquemas fuente están lógicamente separados para seguridad y organización
4. **Esquema de Auditoría**: Esquema de auditoría común para monitoreo y logging entre fuentes

## Conceptos Clave

### Change Data Capture (CDC)

Los mecanismos CDC tradicionales rastrean cambios a nivel de base de datos fuente. Este patrón implementa un enfoque **CDC basado en hash** que:
- Funciona con cualquier sistema fuente (no requiere características CDC a nivel de base de datos)
- Detecta cambios comparando valores hash en lugar de comparación columna por columna
- Proporciona detección eficiente de cambios con overhead computacional mínimo

### Detección de Cambios Basada en Hash

La columna **ChangeHashKey** contiene un hash SHA256 de todas las columnas de negocio relevantes. Esta técnica:
- **Eficiencia**: Comparación única en lugar de múltiples comparaciones de columnas
- **Consistencia**: Determinista - los mismos datos siempre producen el mismo hash
- **Sensibilidad**: Cualquier cambio en datos fuente produce un hash diferente
- **Rendimiento**: La columna hash indexada habilita búsquedas rápidas

**Fórmula**:
```
ChangeHashKey = SHA256(Columna1 + Columna2 + ... + ColumnaN)
```

### Patrón de Eliminación Suave

En lugar de eliminar físicamente registros, el flag **IsDeleted** marca registros como eliminados. Este enfoque:
- **Preserva el Historial**: Los registros eliminados permanecen en la base de datos para propósitos de auditoría
- **Habilita Recuperación**: Los datos eliminados accidentalmente pueden restaurarse
- **Soporta Consultas Temporales**: El análisis puede incluir o excluir registros eliminados
- **Mantiene Contexto Referencial**: Los registros relacionados aún pueden referirse a entidades eliminadas

### Idempotencia

El patrón de actualización es **idempotente**, lo que significa:
- Ejecutar la misma carga múltiples veces produce el mismo resultado
- Las cargas fallidas pueden reintentarse de manera segura sin corrupción de datos
- No se crean registros duplicados
- Soporta estrategias de carga tanto completa como incremental

### Seguimiento Temporal

Cada registro rastrea su ciclo de vida a través de columnas timestamp:
- **InsertDatetime**: Cuándo el registro apareció por primera vez en la Landing zone
- **UpdateDatetime**: Cuándo el registro fue modificado por última vez
- Habilita análisis point-in-time y métricas de tasa de cambio

## Diseño de Esquema

### Convenciones de Nomenclatura

| Elemento | Convención | Ejemplo |
|---------|-----------|---------|
| Base de Datos | PascalCase | `Landing` |
| Esquema Fuente | MAYÚSCULAS | `ERP`, `SALESFORCE`, `MES` |
| Esquema Auditoría | minúsculas | `audit` |
| Nombre de Tabla | Coincide con tabla fuente | `Customer`, `Order` |
| Columnas Clave de Negocio | Coincide con fuente | `CompanyId`, `CustomerId` |
| Columnas Técnicas | PascalCase | `ChangeHashKey`, `InsertDatetime` |

### Patrón Esquema-por-Fuente

Cada sistema fuente obtiene su propio esquema por varias razones:

**Beneficios**:
- **Seguridad**: Otorgar permisos a nivel de esquema (ej. equipo ERP accede solo al esquema `ERP`)
- **Organización**: Clara separación de responsabilidades
- **Evitación de Colisiones**: Diferentes fuentes pueden tener tablas con el mismo nombre (ej. `ERP.Order` vs `SALESFORCE.Order`)
- **Procesamiento Selectivo**: Procesar o recargar fuentes específicas independientemente
- **Documentación**: El nombre del esquema identifica inmediatamente la procedencia de los datos

**Ejemplo**:
```sql
-- Tabla Customer de ERP
ERP.Customer

-- Tabla Account de Salesforce (equivalente a Customer en ERP)
SALESFORCE.Account
```

## Estructura de Tablas

### Diseño Estándar de Columnas

Cada tabla Landing sigue esta estructura:

```sql
CREATE TABLE [ESQUEMA_FUENTE].[NombreTabla]
(
    -- Columnas Clave de Negocio (de la fuente)
    [ClavePrimaria1]   [TipoDatos]      NOT NULL,
    [ClavePrimaria2]   [TipoDatos]      NOT NULL,
    
    -- Detección de Cambios y Metadatos
    [ChangeHashKey]    BINARY(32)      NOT NULL,
    [InsertDatetime]   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    [UpdateDatetime]   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    [IsDeleted]        BIT             NOT NULL DEFAULT 0,
    
    -- Columnas de Negocio (de la fuente)
    [Columna1]         [TipoDatos]      [NULL/NOT NULL],
    [Columna2]         [TipoDatos]      [NULL/NOT NULL],
    ...
    
    -- Restricción de Clave Primaria
    CONSTRAINT [PK_FUENTE_NombreTabla] PRIMARY KEY CLUSTERED 
    (
        [ClavePrimaria1],
        [ClavePrimaria2]
    )
);

-- Índice en ChangeHashKey para rendimiento
CREATE NONCLUSTERED INDEX [IX_FUENTE_NombreTabla_ChangeHashKey] 
    ON [ESQUEMA_FUENTE].[NombreTabla] ([ChangeHashKey]);

-- Índice en columnas temporales para consultas de auditoría
CREATE NONCLUSTERED INDEX [IX_FUENTE_NombreTabla_Temporal] 
    ON [ESQUEMA_FUENTE].[NombreTabla] ([UpdateDatetime], [IsDeleted]);
```

### Descripciones de Columnas

| Columna | Tipo | Propósito | Poblado |
|--------|------|---------|-----------|
| Clave(s) de Negocio | Varía | Identificador único de la fuente | Cada carga |
| ChangeHashKey | BINARY(32) | Hash SHA256 de columnas de negocio | Cada carga (calculado) |
| InsertDatetime | DATETIME | Timestamp de primera inserción | Solo inserción |
| UpdateDatetime | DATETIME | Timestamp de última modificación | Inserción y actualización |
| IsDeleted | BIT | Flag de eliminación suave | Inserción (0) y eliminación (1) |
| Columnas de Negocio | Varía | Columnas de datos fuente | Cada carga |

### Estrategia de Selección de Columnas

**Columnas Clave de Negocio**: Incluir todas las columnas que forman la clave primaria de la tabla fuente
- Estas identifican únicamente cada registro
- Usadas para emparejar datos fuente con datos landing

**Columnas de Negocio**: Incluir solo las columnas necesarias para procesamiento downstream
- No todas las columnas fuente necesitan estar en el data warehouse
- Seleccionar columnas relevantes para inteligencia de negocios y reportes
- Excluir datos sensibles si no son necesarios (minimiza requisitos de cumplimiento)
- Excluir columnas binarias grandes (imágenes, documentos) a menos que se requieran específicamente

**Cálculo de ChangeHashKey**: Hashear solo las columnas de negocio
- NO incluir columnas clave de negocio (no cambian)
- NO incluir columnas técnicas (InsertDatetime, UpdateDatetime, IsDeleted)
- Incluir TODAS las columnas en las que quieres detectar cambios

## Patrón de Actualización

### Los Cuatro Escenarios

La lógica de actualización sigue un **patrón similar a MERGE** que maneja cuatro escenarios distintos:

```
┌─────────────────────────────────────────────────────────────┐
│                 Extracción de Tabla Fuente                  │
│         (Claves Primarias + Columnas de Negocio)            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ├─ Calcular ChangeHashKey
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│           Emparejar con Tabla Landing en PK                 │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │Escenario│    │Escenario│    │Escenario│
    │    A    │    │  B y C  │    │    D    │
    └─────────┘    └─────────┘    └─────────┘
```

#### Escenario A: Nuevo Registro
**Condición**: El registro existe en fuente pero NO en landing

**Acción**: INSERT nuevo registro
```sql
INSERT INTO [Landing].[ESQUEMA].[Tabla]
(
    [ClavePrimaria1],
    [ClavePrimaria2],
    [ChangeHashKey],
    [InsertDatetime],
    [UpdateDatetime],
    [IsDeleted],
    [Columna1],
    [Columna2]
)
VALUES
(
    @ClavePrimaria1,
    @ClavePrimaria2,
    @HashCalculado,           -- Hash SHA256
    CURRENT_TIMESTAMP,        -- Establecer hora de inserción
    CURRENT_TIMESTAMP,        -- Establecer hora de actualización
    0,                        -- No eliminado
    @Columna1,
    @Columna2
);
```

**Ejemplo**: Se crea un nuevo cliente en el sistema ERP
- Primera vez que este cliente aparece en el data warehouse
- Todos los campos se pueblan desde la fuente
- InsertDatetime y UpdateDatetime establecidos a hora actual

#### Escenario B: Sin Cambios
**Condición**: El registro existe tanto en fuente como en landing, ChangeHashKey coincide

**Acción**: SIN ACCIÓN (omitir registro)
```sql
-- Pseudocódigo
IF fuente.ChangeHashKey = landing.ChangeHashKey THEN
    SKIP; -- Sin cambios detectados
END IF;
```

**Ejemplo**: Los datos del cliente no han cambiado desde la última carga
- La comparación de hash es muy rápida (comparación de valor único)
- Minimiza actualizaciones innecesarias
- Preserva UpdateDatetime para reflejar el tiempo de cambio real

#### Escenario C: Registro Modificado
**Condición**: El registro existe tanto en fuente como en landing, ChangeHashKey difiere

**Acción**: UPDATE registro existente
```sql
UPDATE [Landing].[ESQUEMA].[Tabla]
SET
    [ChangeHashKey] = @NuevoHashCalculado, -- Actualizar hash
    [UpdateDatetime] = CURRENT_TIMESTAMP,  -- Actualizar timestamp
    [Columna1] = @NuevaColumna1,           -- Actualizar columnas de negocio
    [Columna2] = @NuevaColumna2
WHERE
    [ClavePrimaria1] = @ClavePrimaria1
    AND [ClavePrimaria2] = @ClavePrimaria2;
```

**Ejemplo**: El nombre o número de IVA del cliente cambió en ERP
- El hash detecta automáticamente el cambio
- Todas las columnas de negocio se actualizan (incluso si solo una cambió)
- UpdateDatetime refleja cuándo se detectó el cambio
- InsertDatetime permanece sin cambios (tiempo de llegada original preservado)

#### Escenario D: Registro Eliminado
**Condición**: El registro existe en landing (IsDeleted = 0) pero NO en fuente

**Acción**: ELIMINACIÓN SUAVE (marcar como eliminado)
```sql
UPDATE [Landing].[ESQUEMA].[Tabla]
SET
    [UpdateDatetime] = CURRENT_TIMESTAMP,   -- Actualizar timestamp
    [IsDeleted] = 1                         -- Marcar como eliminado
WHERE
    [ClavePrimaria1] = @ClavePrimaria1
    AND [ClavePrimaria2] = @ClavePrimaria2
    AND [IsDeleted] = 0;                    -- Solo actualizar si no ya eliminado
```

**Ejemplo**: Registro de cliente eliminado del ERP
- El registro permanece en la tabla Landing para propósitos de auditoría
- El flag IsDeleted previene procesamiento en capas downstream
- UpdateDatetime refleja cuándo se detectó la eliminación
- Puede consultarse para análisis histórico

**Nota**: Los registros con `IsDeleted = 1` NO se re-eliminan si siguen ausentes en cargas subsiguientes

### Enfoques de Implementación

#### Opción 1: Instrucción MERGE (Recomendada)
```sql
MERGE [Landing].[ERP].[Customer] AS target
USING #DatosFuente AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Escenario C: Actualizar cuando hash cambió
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- Escenario A: Insertar nuevos registros
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

-- Escenario D: Eliminación suave de registros faltantes
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

#### Opción 2: Instrucciones Separadas
```sql
-- Escenario A: Insertar nuevos registros
INSERT INTO [Landing].[ERP].[Customer] (...)
SELECT ...
FROM #DatosFuente s
WHERE NOT EXISTS (
    SELECT 1 FROM [Landing].[ERP].[Customer] t
    WHERE t.CompanyId = s.CompanyId AND t.CustomerId = s.CustomerId
);

-- Escenario C: Actualizar registros modificados
UPDATE t
SET ...
FROM [Landing].[ERP].[Customer] t
INNER JOIN #DatosFuente s 
    ON t.CompanyId = s.CompanyId AND t.CustomerId = s.CustomerId
WHERE t.ChangeHashKey <> s.ChangeHashKey;

-- Escenario D: Eliminación suave de registros faltantes
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0
    AND NOT EXISTS (
        SELECT 1 FROM #DatosFuente s
        WHERE s.CompanyId = t.CompanyId AND s.CustomerId = t.CustomerId
    );
```

## Beneficios y Justificación

### ¿Por Qué Detección de Cambios Basada en Hash?

**Enfoque Tradicional** (comparación columna por columna):
```sql
WHERE target.Columna1 <> source.Columna1
   OR target.Columna2 <> source.Columna2
   OR target.Columna3 <> source.Columna3
   ...
```
**Problemas**:
- Cláusula WHERE compleja para tablas con muchas columnas
- Manejo de NULL requiere lógica especial (ISNULL o COALESCE)
- El rendimiento se degrada con más columnas
- Difícil de mantener a medida que el esquema evoluciona

**Enfoque Basado en Hash**:
```sql
WHERE target.ChangeHashKey <> source.ChangeHashKey
```
**Ventajas**:
- ✅ Comparación única independientemente del número de columnas
- ✅ Determinista y consistente
- ✅ Manejo de NULL integrado en cálculo de hash
- ✅ Puede indexarse para rendimiento
- ✅ Fácil de mantener y entender

### ¿Por Qué Eliminaciones Suaves?

**Eliminación Dura** (eliminación física):
```sql
DELETE FROM [Landing].[ERP].[Customer]
WHERE ...
```
**Problemas**:
- Datos históricos perdidos para siempre
- Pista de auditoría rota
- No se puede distinguir "nunca existió" de "fue eliminado"
- No se puede rastrear cuándo ocurrió la eliminación

**Eliminación Suave** (flag IsDeleted):
```sql
UPDATE [Landing].[ERP].[Customer]
SET IsDeleted = 1
WHERE ...
```
**Ventajas**:
- ✅ Pista de auditoría completa mantenida
- ✅ Posibilidad de restaurar datos eliminados accidentalmente
- ✅ Los procesos downstream pueden elegir incluir/excluir registros eliminados
- ✅ El análisis temporal permanece preciso
- ✅ Cumplimiento regulatorio (GDPR, SOX, etc.) más fácil

### ¿Por Qué Esquema-por-Fuente?

**Enfoque de Esquema Único**:
```
Landing.dbo.ERP_Customer
Landing.dbo.ERP_Order
Landing.dbo.Salesforce_Account
Landing.dbo.Salesforce_Opportunity
```
**Problemas**:
- Las colisiones de nombres de tablas requieren prefijos
- La seguridad debe gestionarse a nivel de tabla
- Difícil otorgar acceso a "todas las tablas ERP"
- Contaminación del namespace

**Enfoque Esquema-por-Fuente**:
```
Landing.ERP.Customer
Landing.ERP.Order
Landing.SALESFORCE.Account
Landing.SALESFORCE.Opportunity
```
**Ventajas**:
- ✅ Separación natural del namespace
- ✅ Grants de seguridad a nivel de esquema
- ✅ Clara trazabilidad de datos
- ✅ Más fácil recargar fuente completa
- ✅ Los nombres de tablas coinciden exactamente con el sistema fuente

### ¿Por Qué Columnas Temporales?

**InsertDatetime** habilita:
- Identificar cuándo los registros entraron por primera vez al data warehouse
- Medir latencia de datos (tiempo desde creación en fuente hasta llegada)
- Depurar procesos ETL
- Requisitos de cumplimiento y auditoría

**UpdateDatetime** habilita:
- Análisis de frecuencia de cambios
- Identificar datos obsoletos
- Solucionar problemas de calidad de datos
- Monitoreo de SLA (¿qué tan frescos son los datos?)
- Procesamiento incremental en capas downstream

## Ejemplos

### Ejemplo 1: Tabla Customer de ERP

**Tabla Fuente** (base de datos ERP):
```sql
-- dbo.Customer en base de datos ERP
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

**Tabla Landing** (base de datos Landing):
```sql
-- ERP.Customer en base de datos Landing
CREATE TABLE [Landing].[ERP].[Customer]
(
    -- Claves de Negocio
    CompanyId           INT             NOT NULL,
    CustomerId          INT             NOT NULL,
    
    -- Columnas Técnicas
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdateDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Columnas de Negocio (seleccionadas de la fuente)
    CustomerName        NVARCHAR(100)   NOT NULL,
    VAT                 NVARCHAR(20)    NULL,
    
    CONSTRAINT PK_ERP_Customer PRIMARY KEY CLUSTERED (CompanyId, CustomerId)
);

CREATE NONCLUSTERED INDEX IX_ERP_Customer_ChangeHashKey 
    ON [Landing].[ERP].[Customer] (ChangeHashKey);
```

**Cálculo de Hash** (pseudocódigo):
```
ChangeHashKey = SHA256(CustomerName + '|' + ISNULL(VAT, ''))
```

**Nota**: Address y CreditLimit NO están incluidos (no necesarios en DW)

### Ejemplo 2: Proceso ETL Completo

**Paso 1**: Extraer de la fuente
```sql
-- Extraer datos del ERP
SELECT 
    CompanyId,
    CustomerId,
    CustomerName,
    VAT,
    -- Calcular hash
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey
INTO #DatosFuente
FROM [Servidor_ERP].[ERP].[dbo].[Customer];
```

**Paso 2**: Aplicar lógica MERGE
```sql
MERGE [Landing].[ERP].[Customer] AS target
USING #DatosFuente AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Actualizar registros modificados (Escenario C)
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- Insertar nuevos registros (Escenario A)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

-- Eliminación suave de registros faltantes (Escenario D)
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

**Paso 3**: Registrar resultados (en esquema audit)
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
    @ConteoInsertados,
    @ConteoActualizados,
    @ConteoEliminados,
    CURRENT_TIMESTAMP
);
```

### Ejemplo 3: Recorrido de Escenarios

**Estado Inicial** (tabla Landing):
```
CompanyId | CustomerId | ChangeHashKey | CustomerName  | VAT        | IsDeleted
----------|------------|---------------|---------------|------------|----------
1         | 100        | 0xABCD...     | Acme Corp     | IT12345    | 0
1         | 101        | 0xEF01...     | Beta LLC      | IT67890    | 0
```

**Datos Fuente** (ERP actual):
```
CompanyId | CustomerId | CustomerName      | VAT        
----------|------------|-------------------|------------
1         | 100        | Acme Corp         | IT12345    
1         | 101        | Beta Industries   | IT67890    
1         | 102        | Gamma Solutions   | IT11111    
```

**Procesamiento**:

1. **Cliente 100**: Hash coincide → Escenario B (sin acción)
   - Sin cambios detectados
   - Registro no tocado

2. **Cliente 101**: Hash difiere → Escenario C (actualización)
   - CustomerName cambió de "Beta LLC" a "Beta Industries"
   - Nuevo hash calculado
   - UpdateDatetime actualizado
   - Columnas de negocio actualizadas

3. **Cliente 102**: No en landing → Escenario A (inserción)
   - Nuevo cliente creado en ERP
   - Nuevo registro insertado
   - InsertDatetime y UpdateDatetime establecidos

**Resultado**:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName      | VAT     | IsDeleted | UpdateDatetime
----------|------------|---------------|-------------------|---------|-----------|----------------
1         | 100        | 0xABCD...     | Acme Corp         | IT12345 | 0         | (sin cambios)
1         | 101        | 0x1234...     | Beta Industries   | IT67890 | 0         | 2026-05-20 10:30
1         | 102        | 0x5678...     | Gamma Solutions   | IT11111 | 0         | 2026-05-20 10:30
```

## Mejores Prácticas

### 1. Cálculo de Hash

**Delimitadores Consistentes**:
```sql
-- Bien: Usar delimitador para evitar ambigüedad de concatenación
HASHBYTES('SHA2_256', CONCAT(Col1, '|', Col2, '|', Col3))

-- Mal: Valores "AB" + "CD" produce mismo resultado que "ABC" + "D"
HASHBYTES('SHA2_256', CONCAT(Col1, Col2, Col3))
```

**Manejo de NULL**:
```sql
-- Bien: Manejo explícito de NULL
HASHBYTES('SHA2_256', 
    CONCAT(
        Col1, '|',
        ISNULL(Col2, ''), '|',
        ISNULL(Col3, '')
    )
)

-- Mal: Propagación de NULL hace todo el hash NULL
HASHBYTES('SHA2_256', CONCAT(Col1, '|', Col2, '|', Col3))
```

**Consistencia de Tipo de Datos**:
```sql
-- Bien: Convertir a cadena de manera consistente
HASHBYTES('SHA2_256', 
    CONCAT(
        StringCol, '|',
        CAST(NumericCol AS NVARCHAR(50)), '|',
        CONVERT(NVARCHAR(23), DateCol, 121)  -- Formato ISO
    )
)
```

### 2. Optimización de Rendimiento

**Estrategia de Indexación**:
```sql
-- Clave primaria para operaciones MERGE
CREATE PRIMARY KEY (ClaveNegocio1, ClaveNegocio2);

-- Índice hash para detección de cambios
CREATE INDEX IX_ChangeHash ON Tabla (ChangeHashKey);

-- Índice temporal para consultas de auditoría
CREATE INDEX IX_Temporal ON Tabla (UpdateDatetime, IsDeleted) 
    INCLUDE (ClaveNegocio1, ClaveNegocio2);

-- Índice compuesto para procesamiento downstream
CREATE INDEX IX_Active ON Tabla (IsDeleted) 
    WHERE IsDeleted = 0;  -- Índice filtrado para registros activos
```

**Usar Tablas Temporales**:
```sql
-- Extraer primero a tabla temporal
SELECT ... INTO #DatosFuente FROM [ServidorEnlazado].[BaseDatos].[Esquema].[Tabla];

-- Crear índices en tabla temporal
CREATE INDEX IX_Temp ON #DatosFuente (ClavePrimaria1, ClavePrimaria2);

-- Luego MERGE
MERGE [Landing].[Esquema].[Tabla] AS target
USING #DatosFuente AS source ...
```

### 3. Manejo de Errores

**Gestión de Transacciones**:
```sql
BEGIN TRY
    BEGIN TRANSACTION;
    
    -- Extracción
    SELECT ... INTO #DatosFuente FROM ...;
    
    -- Transformación (calcular hash)
    UPDATE #DatosFuente SET ChangeHashKey = HASHBYTES(...);
    
    -- Carga (MERGE)
    MERGE [Landing].[Esquema].[Tabla] ...;
    
    -- Auditoría
    INSERT INTO [audit].[ETLLog] ...;
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    -- Registrar error
    INSERT INTO [audit].[ETLError] (
        SourceSchema, SourceTable, ErrorMessage, ErrorDatetime
    )
    VALUES (
        'ERP', 'Customer', ERROR_MESSAGE(), CURRENT_TIMESTAMP
    );
    
    THROW;
END CATCH;
```

### 4. Diseño de Esquema de Auditoría

**Tabla de Log ETL**:
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
    ExecutionDuration   INT             NULL,  -- milisegundos
    RowsProcessed       INT             NULL
);
```

**Vista de Monitoreo**:
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
    FROM [Landing].[esquema].[tabla]  -- SQL dinámico necesario en práctica
) x
WHERE s.name NOT IN ('audit', 'dbo', 'sys')
GROUP BY s.name, t.name;
```

### 5. Verificaciones de Calidad de Datos

**Validación Post-Carga**:
```sql
-- Verificar claves foráneas huérfanas
SELECT 'Pedidos Huérfanos' AS Problema, COUNT(*) AS Conteo
FROM [Landing].[ERP].[Order] o
WHERE NOT EXISTS (
    SELECT 1 FROM [Landing].[ERP].[Customer] c
    WHERE c.CompanyId = o.CompanyId 
    AND c.CustomerId = o.CustomerId
    AND c.IsDeleted = 0
);

-- Verificar valores NULL inesperados
SELECT 'Nombres Cliente NULL' AS Problema, COUNT(*) AS Conteo
FROM [Landing].[ERP].[Customer]
WHERE CustomerName IS NULL
AND IsDeleted = 0;

-- Verificar claves de negocio duplicadas (nunca debería pasar)
SELECT 'Clientes Duplicados' AS Problema, COUNT(*) AS Conteo
FROM (
    SELECT CompanyId, CustomerId, COUNT(*) AS Cnt
    FROM [Landing].[ERP].[Customer]
    GROUP BY CompanyId, CustomerId
    HAVING COUNT(*) > 1
) x;
```

### 6. Carga Incremental vs Completa

**Carga Completa** (recomendada para Landing):
- Cargar todos los datos fuente cada vez
- Lógica simple
- Idempotente (seguro re-ejecutar)
- Detecta eliminaciones automáticamente (Escenario D)
- Recomendado para capa Landing

**Carga Incremental** (usar con precaución):
- Cargar solo registros modificados (basado en timestamp fuente)
- Lógica más compleja
- Más rápido para tablas muy grandes
- Detección de eliminaciones requiere lógica separada
- Considerar para capas downstream, no Landing

**Ejemplo - Carga Completa con optimización TRUNCATE**:
```sql
-- Para tablas de dimensión pequeñas, truncate y reload puede ser más rápido que MERGE
BEGIN TRANSACTION;

    TRUNCATE TABLE [Landing].[ERP].[CustomerCategory];
    
    INSERT INTO [Landing].[ERP].[CustomerCategory] (...)
    SELECT ... FROM [Servidor_ERP].[ERP].[dbo].[CustomerCategory];

COMMIT TRANSACTION;
```

### 7. Evolución de Esquema

Cuando el esquema fuente cambia:

**Agregar Columnas**:
```sql
-- 1. Agregar columna a tabla Landing
ALTER TABLE [Landing].[ERP].[Customer]
ADD EmailAddress NVARCHAR(100) NULL;

-- 2. Actualizar cálculo de hash para incluir nueva columna
-- (actualizar procedimiento ETL)

-- 3. La siguiente carga detectará TODOS los registros como modificados
-- (el hash cambia porque el cálculo incluye la nueva columna)
-- Esto es comportamiento esperado y correcto
```

**Eliminar Columnas**:
```sql
-- 1. Actualizar cálculo de hash (eliminar columna)
-- 2. La siguiente carga detectará TODOS los registros como modificados
-- 3. Posteriormente: eliminar columna de tabla Landing (opcional)
ALTER TABLE [Landing].[ERP].[Customer]
DROP COLUMN ColumnaAntigua;
```

**Mejor Práctica**: Versiona tu cálculo de hash
```sql
-- Opción 1: Agregar columna versión de hash
ALTER TABLE [Landing].[ERP].[Customer]
ADD HashVersion TINYINT NOT NULL DEFAULT 1;

-- Opción 2: Incluir versión en hash
ChangeHashKey = HASHBYTES('SHA2_256', CONCAT('v2|', Col1, '|', Col2, ...))
```

---

## Resumen

Este patrón de diseño de Landing zone proporciona:

✅ **Escalabilidad**: Maneja múltiples sistemas fuente independientemente  
✅ **Rendimiento**: Detección de cambios basada en hash es rápida y eficiente  
✅ **Auditabilidad**: Seguimiento temporal completo y eliminaciones suaves  
✅ **Confiabilidad**: Cargas idempotentes pueden reintentarse de manera segura  
✅ **Mantenibilidad**: Estructura clara y patrones consistentes  
✅ **Flexibilidad**: Funciona con cualquier sistema fuente (sin requisitos CDC)  

Siguiendo estos principios, creas una base robusta para tu data warehouse que desacopla sistemas fuente, rastrea cambios eficientemente y mantiene pistas de auditoría completas para cumplimiento y análisis.

---

**Versión del Documento**: 1.0  
**Última Actualización**: 20 de mayo de 2026  
**Stack Tecnológico**: Microsoft SQL Server 2016+
