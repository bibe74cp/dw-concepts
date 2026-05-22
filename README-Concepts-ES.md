# Arquitectura del Data Warehouse - Conceptos Fundamentales

## Tabla de Contenidos
- [Introducción](#introducción)
- [¿Qué es un Data Warehouse?](#qué-es-un-data-warehouse)
- [La Arquitectura de Dos Capas](#la-arquitectura-de-dos-capas)
- [Conceptos Fundamentales Explicados](#conceptos-fundamentales-explicados)
- [El Viaje de los Datos](#el-viaje-de-los-datos)
- [Beneficios Clave](#beneficios-clave)
- [Analogía del Mundo Real](#analogía-del-mundo-real)
- [Lectura Adicional](#lectura-adicional)

## Introducción

Este documento explica la arquitectura y los conceptos detrás de nuestro sistema de data warehouse en un lenguaje claro y no técnico. Ya seas analista de negocios, gerente o parte interesada, esta guía te ayudará a entender cómo organizamos, almacenamos y preparamos datos para inteligencia de negocios y generación de reportes.

Nuestro enfoque se basa en la **metodología Kimball**, un estándar de la industria ampliamente reconocido para construir data warehouses que ha demostrado ser exitoso en miles de organizaciones en todo el mundo desde los años 90.

## ¿Qué es un Data Warehouse?

### Definición

Un **data warehouse** es un repositorio centralizado donde se recopilan, organizan y preparan datos de varios sistemas empresariales (como ERP, CRM o sistemas de manufactura) para análisis y generación de reportes.

Piénsalo como una biblioteca para tus datos empresariales:
- Así como una biblioteca recopila libros de varios editores y los organiza para facilitar su descubrimiento
- Un data warehouse recopila datos de varios sistemas empresariales y los organiza para facilitar el análisis

**Diferencias clave respecto a los sistemas operacionales:**

| Sistema Operacional (ERP, CRM) | Data Warehouse |
|-------------------------------|----------------|
| Diseñado para transacciones diarias | Diseñado para análisis y reportes |
| Optimizado para velocidad de actualizaciones | Optimizado para velocidad de consultas |
| Almacena datos actuales | Almacena datos históricos a lo largo del tiempo |
| Usado por empleados haciendo su trabajo | Usado por analistas y tomadores de decisiones |
| Datos organizados para eficiencia | Datos organizados para comprensión |

### ¿Por Qué Necesitamos un Data Warehouse?

**Problema**: Tus datos empresariales viven en muchos sistemas diferentes:
- Datos de clientes en tu CRM (Salesforce)
- Datos de pedidos en tu sistema ERP
- Datos de producción en tu sistema de manufactura
- Cada sistema tiene su propia estructura y terminología

**Solución**: Un data warehouse:
- ✅ Reúne todos los datos en un solo lugar
- ✅ Los organiza de manera consistente y comprensible
- ✅ Preserva cambios históricos a lo largo del tiempo
- ✅ Hace que sea rápido responder preguntas de negocios
- ✅ No ralentiza tus sistemas operacionales

**Lectura adicional**: [Data Warehouse - Wikipedia](https://es.wikipedia.org/wiki/Almac%C3%A9n_de_datos)

## La Arquitectura de Dos Capas

Nuestro data warehouse utiliza una **arquitectura de dos capas**, cada una sirviendo un propósito específico en el viaje de los datos desde los sistemas fuente hasta los reportes empresariales.

```
Sistemas Fuente → Landing Zone → Data Warehouse → Reportes & Analytics
(ERP, CRM, MES)   (Capa 1)       (Capa 2)        (Power BI, Excel)
```

### Capa 1: La Landing Zone

**Propósito**: Un área de staging segura donde los datos crudos llegan por primera vez desde los sistemas fuente.

**Analogía**: Piensa en un muelle de carga en un almacén:
- Los paquetes (datos) llegan de diferentes proveedores (sistemas fuente)
- Cada uno es revisado, etiquetado y organizado
- Nada se descarta; todo se rastrea
- Los problemas de calidad se identifican antes de pasar al almacenamiento

**Qué sucede aquí:**
- Los datos se copian de los sistemas fuente (ERP, Salesforce, etc.)
- Cada sistema fuente obtiene su propio espacio organizado
- Los cambios se rastrean (qué es nuevo, qué cambió, qué se eliminó)
- La calidad de los datos se verifica
- Se mantiene una pista de auditoría completa

**Principio clave**: La Landing Zone es una **copia fiel** de los datos fuente con transformaciones mínimas. Rastreamos de dónde vienen los datos y cuándo llegaron.

### Capa 2: El Data Warehouse

**Propósito**: Almacenamiento organizado optimizado para análisis empresarial y generación de reportes.

**Analogía**: Piensa en una biblioteca empresarial bien organizada:
- Los libros (datos) están catalogados por tema (dimensiones como Cliente, Producto, Fecha)
- Los eventos (como transacciones de ventas) hacen referencia a estos temas
- La información relacionada se mantiene junta
- Fácil de encontrar lo que necesitas para cualquier pregunta

**Qué sucede aquí:**
- Los datos de múltiples fuentes se combinan y unifican
- Se aplican nombres y estructuras amigables para el negocio
- Organizados en **dimensiones** (quién, qué, cuándo, dónde) y **hechos** (mediciones, eventos)
- Optimizados para responder rápidamente preguntas de negocios
- Se crean vistas curadas para departamentos o aplicaciones específicas

**Principio clave**: El Data Warehouse está organizado alrededor de **procesos de negocio** (como Ventas, Producción, Inventario) en lugar de sistemas técnicos.

## Conceptos Fundamentales Explicados

### Modelado Dimensional (Metodología Kimball)

El **modelado dimensional** es una técnica de diseño que organiza los datos en dos tipos de tablas:

1. **Tablas de Dimensiones**: Describen el contexto empresarial (el "QUIÉN, QUÉ, CUÁNDO, DÓNDE, POR QUÉ")
2. **Tablas de Hechos**: Registran mediciones y eventos (el "CUÁNTO, CUÁNTOS")

Este enfoque fue pionero de **Ralph Kimball**, un arquitecto líder de data warehouse, y está documentado en su influyente libro "The Data Warehouse Toolkit".

**Por qué es importante:**
- Hace que los datos sean intuitivos de entender para los usuarios empresariales
- Habilita consultas y reportes rápidos
- Flexible para responder preguntas inesperadas
- Enfoque probado por la industria usado en todo el mundo

**Lectura adicional**: 
- [Modelado Dimensional - Wikipedia](https://en.wikipedia.org/wiki/Dimensional_modeling)
- [Esquema en Estrella - Wikipedia](https://es.wikipedia.org/wiki/Esquema_en_estrella)

### Dimensiones: El Contexto de Tu Negocio

Las **dimensiones** son los sustantivos de tu negocio - las personas, productos, ubicaciones y períodos de tiempo que proporcionan contexto a tus métricas.

**Ejemplos de dimensiones:**
- **Cliente**: ¿Quién compró algo? (nombre, categoría, región, segmento)
- **Producto**: ¿Qué se vendió? (nombre, categoría, marca, tamaño)
- **Fecha**: ¿Cuándo sucedió? (día, semana, mes, trimestre, año)
- **Empleado**: ¿Quién estuvo involucrado? (nombre, departamento, rol, gerente)
- **Ubicación**: ¿Dónde ocurrió? (tienda, almacén, región, país)

**Piensa en las dimensiones como las preguntas que haces:**
- "Muéstrame las ventas por **cliente**"
- "Muéstrame la producción por **producto** y **fecha**"
- "Muéstrame los pedidos por **región** y **empleado**"

**Características clave:**
- Relativamente pequeñas (cientos a millones de filas)
- Atributos descriptivos (texto, categorías, jerarquías)
- Cambian lentamente con el tiempo
- Usadas para filtrar, agrupar y etiquetar tus reportes

### Hechos: Las Mediciones de Tu Negocio

Los **hechos** son los verbos y mediciones de tu negocio - las transacciones, eventos y métricas que quieres analizar.

**Ejemplos de hechos:**
- **Transacción de Venta**: Un cliente compró un producto por cierta cantidad
- **Orden de Producción**: Se manufacturó una cantidad de productos
- **Snapshot de Inventario**: El nivel de stock en un punto en el tiempo
- **Visita al Sitio Web**: Un cliente visualizó una página durante cierta duración

**Piensa en los hechos como las respuestas que buscas:**
- "**¿Cuánto** vendimos?"
- "**¿Cuántas** unidades se produjeron?"
- "**¿Cuál fue** el valor del inventario?"

**Características clave:**
- Muy grandes (millones a miles de millones de filas)
- Mediciones numéricas (cantidades, montos, duraciones)
- Cada fila representa un evento de negocio específico
- Hace referencia a dimensiones para proporcionar contexto

### El Esquema en Estrella: Cómo Se Conecta Todo

El **esquema en estrella** es la disposición de dimensiones alrededor de los hechos, pareciendo una estrella:

```
        Cliente
           |
           |
Producto -- HECHO VENTAS -- Fecha
           |
           |
        Empleado
```

**Cómo leerlo:**
- El centro (HECHO VENTAS) contiene mediciones: cantidad vendida, ingresos, beneficio
- Cada punto de la estrella (dimensiones) proporciona contexto: quién, qué, cuándo, dónde
- Para responder "¿Cuáles fueron las ventas por producto y cliente?", simplemente conectas los puntos

**Beneficios para usuarios no técnicos:**
- Estructura intuitiva que coincide con cómo piensas sobre el negocio
- Fácil de entender sin experiencia técnica
- Rápido de consultar y generar reportes
- Flexible para análisis ad-hoc

**Lectura adicional**: [Esquema en Estrella - Wikipedia](https://es.wikipedia.org/wiki/Esquema_en_estrella)

### Seguimiento de Cambios: Saber Qué Cambió y Cuándo

**El desafío empresarial:**
- Las direcciones de los clientes cambian
- Los precios de los productos cambian
- Los roles de los empleados cambian
- ¿Cómo manejamos estos cambios en nuestros datos históricos?

**Nuestro enfoque - Detección de Cambios Basada en Hash:**

En lugar de comparar cada columna para detectar cambios, usamos una técnica llamada **hashing**:
- Piénsalo como una huella digital para cada registro
- Si cualquier dato cambia, la huella digital cambia
- Podemos identificar rápidamente qué es diferente sin examinar cada detalle

**Beneficios:**
- Detección rápida de cambios (milisegundos vs. minutos)
- Precisión completa (cualquier cambio es capturado)
- Funciona con cualquier sistema fuente
- Uso eficiente de recursos computacionales

**Lectura adicional**: [Función Hash - Wikipedia](https://es.wikipedia.org/wiki/Funci%C3%B3n_hash)

### Eliminaciones Suaves: Nunca Perder el Historial

**El desafío empresarial:**
Cuando un cliente es eliminado de tu CRM o un producto es descontinuado, ¿deberíamos eliminarlo del data warehouse?

**Nuestro enfoque - Eliminación Suave:**

En lugar de eliminar físicamente los registros, los **marcamos como eliminados** mientras mantenemos los datos:
- El registro permanece en la base de datos
- Marcado como "eliminado" para que no aparezca en reportes actuales
- Aún disponible para análisis histórico

**Ejemplo del mundo real:**
- Un cliente cierra su cuenta en enero de 2025
- Lo marcamos como eliminado pero mantenemos sus datos
- Los reportes para 2024 aún muestran sus ventas (porque era cliente entonces)
- Los reportes para 2026 lo excluyen (porque ya no es cliente)
- Si regresa en 2027, podemos reactivarlo con todo el historial intacto

**Beneficios:**
- Pista de auditoría completa (cumplimiento regulatorio)
- Los reportes históricos permanecen precisos
- Posibilidad de recuperarse de eliminaciones accidentales
- Posibilidad de analizar patrones (¿por qué los clientes se van?)

### Claves Sustitutas: Identificadores Estables

**El desafío empresarial:**
- Diferentes sistemas usan diferentes IDs de cliente
- Los IDs de cliente pueden reutilizarse o cambiarse
- Las claves compuestas (como Compañía + Cliente) son engorrosas

**Nuestro enfoque - Claves Sustitutas:**

Asignamos nuestros propios identificadores simples y estables:
- Cada cliente obtiene un número único (1, 2, 3, ...) que nunca cambia
- Este número es independiente del sistema fuente
- Hace que conectar datos sea simple y rápido

**Analogía**: Como un número de tarjeta de biblioteca:
- Tu número de tarjeta de biblioteca (clave sustituta) nunca cambia
- Incluso si cambias tu dirección o número de teléfono (claves naturales)
- La biblioteca siempre puede encontrar tus registros usando tu número de tarjeta

**Beneficios:**
- Búsquedas simples y rápidas
- Independiente de cambios en el sistema fuente
- Habilita integración entre múltiples sistemas
- Soporta seguimiento histórico

**Lectura adicional**: [Clave Sustituta - Wikipedia](https://es.wikipedia.org/wiki/Clave_sustituta)

### Miembros Especiales: Manejo de Datos Faltantes

**El desafío empresarial:**
¿Qué sucede cuando un hecho hace referencia a una dimensión que no existe?
- Un pedido sin cliente asignado
- Una venta donde no conocemos el producto
- Una transacción de un empleado desconocido

**Nuestro enfoque - Miembros Especiales:**

Creamos dos registros especiales en cada dimensión:

1. **Miembro Vacío** (No Aplicable):
   - Usado cuando la dimensión no aplica
   - Ejemplo: Un pedido colocado por el sistema no tiene vendedor

2. **Miembro Desconocido** (Referencia Faltante):
   - Usado cuando esperábamos un valor pero está ausente o es inválido
   - Ejemplo: Un pedido hace referencia al cliente #999 pero ese cliente no existe

**Beneficios:**
- Todas las transacciones se cargan exitosamente (sin pérdida de datos)
- Posibilidad de identificar y corregir problemas de calidad de datos
- Los reportes funcionan sin errores
- Mantiene la integridad de los datos

**Ejemplo del mundo real:**
En tu reporte de ventas, podrías ver:
- La mayoría de las ventas asignadas a clientes reales
- Algunas a "(Desconocido)" - indicando un problema de calidad de datos para investigar
- Algunas a "(No Aplicable)" - pedidos generados por el sistema sin cliente

### Idempotencia: Seguro de Ejecutar Repetidamente

**El desafío empresarial:**
¿Qué sucede si una carga de datos falla a la mitad? ¿O se ejecuta dos veces por error?

**Nuestro enfoque - Carga Idempotente:**

La misma carga de datos puede ejecutarse múltiples veces y siempre produce el mismo resultado:
- Ejecutar una vez = mismo resultado que ejecutar diez veces
- Las cargas fallidas pueden reintentarse de manera segura
- No se crean registros duplicados
- Sin corrupción de datos

**Analogía**: Como un interruptor de luz:
- Actívalo "encendido" una vez - la luz se enciende
- Actívalo "encendido" de nuevo - la luz permanece encendida (no se rompe)
- Misma acción, mismo resultado

**Beneficios:**
- Seguro reintentar cargas fallidas
- Posibilidad de programar cargas superpuestas
- Reduce la complejidad operacional
- Aumenta la confiabilidad

**Lectura adicional**: [Idempotencia - Wikipedia](https://es.wikipedia.org/wiki/Idempotencia)

### Seguimiento Temporal: La Línea de Tiempo de Tus Datos

**El concepto empresarial:**
Entender no solo **qué** datos tienes, sino **cuándo** llegaron y cambiaron.

**Qué rastreamos:**
- **Fecha de Inserción**: ¿Cuándo apareció este registro por primera vez en nuestro data warehouse?
- **Fecha de Actualización**: ¿Cuándo se modificó este registro por última vez?
- **Fecha de Eliminación**: ¿Cuándo se marcó este registro como eliminado?

**Valor empresarial:**
- **Frescura de Datos**: ¿Qué tan actuales son nuestras informaciones?
- **Análisis de Cambios**: ¿Con qué frecuencia cambian los detalles de los clientes?
- **Pista de Auditoría**: ¿Quién cambió qué y cuándo?
- **Monitoreo de SLA**: ¿Estamos cumpliendo nuestros compromisos de entrega de datos?
- **Análisis de Tendencias**: ¿Cómo ha evolucionado este cliente con el tiempo?

**Ejemplo del mundo real:**
- Registro de cliente insertado el 1 de enero de 2024 (primera aparición)
- Última actualización el 15 de abril de 2025 (dirección modificada)
- Sin cambios en el último año (cliente estable)
- Esto te dice que el cliente está establecido y es estable

## El Viaje de los Datos

### Paso a Paso: Cómo Fluyen los Datos en el Sistema

#### Paso 1: Extracción desde Sistemas Fuente

**Qué sucede:**
- Cada día (u hora), nos conectamos a tus sistemas operacionales
- Extraemos datos nuevos y modificados
- Sin impacto en el rendimiento del sistema (leemos, nunca escribimos)

**Ejemplo:**
- Conexión a la base de datos ERP
- Lectura de todos los clientes modificados en las últimas 24 horas
- Lectura de todos los nuevos pedidos creados hoy

#### Paso 2: Llegada a la Landing Zone

**Qué sucede:**
- Los datos llegan a la Landing Zone (Capa 1)
- Cada sistema fuente tiene su propia área organizada
- Los cambios se detectan automáticamente usando huellas digitales hash
- Los registros se insertan, actualizan o marcan como eliminados

**Ejemplo:**
- 1,250 clientes verificados
- 47 nuevos clientes insertados
- 23 clientes existentes actualizados (cambios detectados)
- 5 clientes marcados como eliminados (ya no en la fuente)

**Resultado**: Una copia exacta y rastreada de los datos fuente

#### Paso 3: Transformación en Dimensiones y Hechos

**Qué sucede:**
- Los datos se mueven de la Landing Zone al Data Warehouse (Capa 2)
- Combinados con datos de otras fuentes
- Organizados en dimensiones (contexto) y hechos (mediciones)
- Se aplican nombres amigables para el negocio
- Se aplican reglas de calidad

**Ejemplo:**
- Datos de cliente desde ERP + Salesforce → **Dim.Cliente**
- Pedidos desde ERP → **Hecho.Ventas**
- Datos de producción desde MES → **Hecho.Producción**

**Resultado**: Modelo de datos unificado y orientado al negocio

#### Paso 4: Acceso a Través de Vistas de Aplicación

**Qué sucede:**
- Se crean vistas específicas para cada consumidor
- Se aplica seguridad (cada aplicación ve solo lo que necesita)
- Lógica compleja oculta detrás de interfaces simples
- Optimizado para rendimiento

**Ejemplo:**
- ERP ve vista de órdenes de producción
- Power BI ve vista de análisis de ventas
- Finanzas ve vista de reportes de ingresos

**Resultado**: Datos correctos para las personas correctas

#### Paso 5: Reportes y Análisis

**Qué sucede:**
- Los usuarios empresariales conectan sus herramientas (Power BI, Excel, Tableau)
- Hacen preguntas de negocios
- Obtienen respuestas rápidas y precisas
- Crean dashboards y reportes

**Ejemplos de Preguntas:**
- "¿Cuáles fueron las ventas por región el último trimestre?"
- "¿Qué productos son los más rentables?"
- "¿Cómo se compara este año con el año pasado?"
- "¿Qué clientes están en riesgo de irse?"

**Resultado**: Decisiones empresariales basadas en datos

### Frecuencia de Sincronización

**¿Con qué frecuencia se actualizan los datos?**

La frecuencia depende de las necesidades empresariales:

| Tipo de Datos | Frecuencia Típica | Razón Empresarial |
|---------------|-------------------|-------------------|
| Datos Transaccionales (Ventas, Pedidos) | Horaria o Diaria | Necesidad de visibilidad operacional actual |
| Datos Maestros (Clientes, Productos) | Diaria | Cambia con menos frecuencia |
| Datos de Manufactura | Cada 15-60 minutos | Monitoreo de producción en tiempo real |
| Datos Financieros | Diaria o Semanal | Procesos de cierre de fin de mes |
| Datos Externos (Precios de mercado) | Según disponibilidad | Depende del proveedor de datos |

**Compromisos:**
- Más frecuente = más actualizado, pero más procesamiento
- Menos frecuente = más simple, pero menos oportuno
- Ajustamos según tus requisitos empresariales específicos

## Beneficios Clave

### Para Usuarios Empresariales

**1. Única Fuente de Verdad**
- Un solo lugar para encontrar todos los datos empresariales
- Definiciones consistentes entre departamentos
- Todos trabajan con los mismos números

**2. Perspectiva Histórica**
- Ver cómo las cosas han cambiado con el tiempo
- Comparar períodos (este año vs. año pasado)
- Identificar tendencias y patrones

**3. Respuestas Rápidas**
- Los reportes se ejecutan en segundos, no horas
- Sin esperar a TI para extraer datos
- Capacidad de análisis autoservicio

**4. Vista Integrada**
- Ver datos de cliente tanto de ERP como de CRM
- Conectar ventas con producción con inventario
- Imagen completa de las operaciones empresariales

**5. Calidad de Datos**
- Problemas identificados y marcados
- Pista de auditoría completa
- Datos validados y verificados

### Para Equipos de TI y Datos

**1. Escalabilidad**
- Maneja volúmenes de datos en crecimiento
- Soporta múltiples sistemas fuente
- Agrega nuevas fuentes de datos fácilmente

**2. Mantenibilidad**
- Patrones claros y documentados
- Enfoque consistente en todo
- Más fácil entrenar nuevos miembros del equipo

**3. Rendimiento**
- Optimizado para consultas analíticas
- No ralentiza sistemas operacionales
- Uso eficiente de recursos computacionales

**4. Confiabilidad**
- Seguro reintentar cargas fallidas
- Seguimiento completo de errores
- Verificaciones automatizadas de calidad de datos

**5. Seguridad**
- Control de acceso basado en roles
- Aislamiento a nivel de aplicación
- Registro completo de auditoría

### Para la Organización

**1. Mejores Decisiones**
- Acceso a información precisa y oportuna
- Capacidad de analizar tendencias y patrones
- Toma de decisiones basada en evidencia

**2. Cumplimiento Regulatorio**
- Pista de auditoría completa
- Seguimiento de linaje de datos
- Retención de datos históricos

**3. Eficiencia Operacional**
- Reducción del esfuerzo de reportes manuales
- Acceso más rápido a información
- Verificaciones automatizadas de calidad de datos

**4. Ventaja Competitiva**
- Insights sobre comportamiento del cliente
- Análisis de tendencias de mercado
- Oportunidades de optimización operacional

**5. Retorno de Inversión**
- Costos reducidos de reportes
- Tiempo más rápido para obtener insights
- Mejores resultados empresariales

## Analogía del Mundo Real

### El Data Warehouse como Sistema de Biblioteca Moderna

Imagina tu data warehouse como un **sistema moderno de biblioteca municipal**:

#### Sistemas Fuente = Editores
- Diferentes editores (ERP, CRM, MES) producen libros (datos)
- Cada uno tiene su propio formato y estilo
- Nuevas ediciones se publican regularmente

#### Landing Zone = Muelle de Recepción
- Los libros llegan de varios editores
- Cada uno se cataloga y verifica su calidad
- Se anotan daños o páginas faltantes
- Se mantiene registro completo de recepción
- Los libros no se modifican, solo se organizan

#### Data Warehouse = Estanterías de la Biblioteca
- Los libros están organizados por tema (dimensiones)
- Los libros relacionados se agrupan juntos
- El catálogo (claves sustitutas) proporciona búsqueda fácil
- Las guías temáticas (hechos) te ayudan a encontrar lo que necesitas
- Diferentes secciones para diferentes propósitos (esquemas)

#### Dimensiones = Secciones del Catálogo
- **Sección de Autores** (como dimensión Cliente): ¿Quién escribió qué?
- **Sección de Temas** (como dimensión Producto): ¿Qué temas se cubren?
- **Sección de Períodos** (como dimensión Fecha): ¿Cuándo se publicó?

#### Hechos = Registros de Circulación
- **Registro de Préstamo** (como hecho Ventas): ¿Quién tomó prestado qué libro cuándo?
- **Conteo de Referencias** (como hecho Vistas de Página): ¿Cuántas veces se accedió?

#### Vistas de Aplicación = Salas de Lectura
- **Sala de Lectura Infantil**: Solo ve libros para niños
- **Sala de Investigación Empresarial**: Solo ve negocios y economía
- **Sala de Historia Local**: Solo ve materiales regionales
- Cada sala curada para su audiencia

#### Bibliotecarios = Ingenieros de Datos
- Organizan materiales entrantes
- Mantienen precisión del catálogo
- Ayudan a los usuarios a encontrar lo que necesitan
- Aseguran que el sistema funcione sin problemas

#### Usuarios de Biblioteca = Usuarios Empresariales
- Entran y encuentran lo que necesitan
- No necesitan saber de dónde vienen los libros
- Pueden navegar, buscar y analizar
- Llevan conocimiento para tomar decisiones

**Esta analogía ayuda a explicar:**
- Por qué tenemos dos capas (recepción vs. estantería)
- Por qué rastreamos cambios (nuevas ediciones, información actualizada)
- Por qué organizamos por dimensiones (catálogo por temas)
- Por qué creamos vistas especiales (salas de lectura)
- Por qué mantenemos historial (ediciones pasadas)

## Lectura Adicional

### Metodología Kimball
- **Sitio Oficial de Ralph Kimball**: [Kimball Group](https://www.kimballgroup.com/)
- **"The Data Warehouse Toolkit"** por Ralph Kimball (la guía definitiva)
- **Técnicas de Modelado Dimensional**: [Kimball Design Tips](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/)

### Recursos de Wikipedia
- [Data Warehouse](https://es.wikipedia.org/wiki/Almac%C3%A9n_de_datos)
- [Modelado Dimensional](https://en.wikipedia.org/wiki/Dimensional_modeling)
- [Esquema en Estrella](https://es.wikipedia.org/wiki/Esquema_en_estrella)
- [Extract, Transform, Load (ETL)](https://es.wikipedia.org/wiki/Extract,_transform,_load)
- [Business Intelligence](https://es.wikipedia.org/wiki/Inteligencia_empresarial)
- [Online Analytical Processing (OLAP)](https://es.wikipedia.org/wiki/OLAP)
- [Slowly Changing Dimension](https://en.wikipedia.org/wiki/Slowly_changing_dimension)
- [Clave Sustituta](https://es.wikipedia.org/wiki/Clave_sustituta)
- [Data Vault Modeling](https://en.wikipedia.org/wiki/Data_vault_modeling) (enfoque alternativo)

### Estándares y Mejores Prácticas de la Industria
- **TDWI (The Data Warehousing Institute)**: [tdwi.org](https://tdwi.org/)
- **DAMA (Data Management Association)**: [dama.org](https://www.dama.org/)
- **Mejores Prácticas de Microsoft SQL Server**: [Microsoft Docs](https://docs.microsoft.com/es-es/sql/)

### Recursos Académicos y Profesionales
- **Corporate Information Factory de Bill Inmon**: Arquitectura alternativa de data warehouse
- **Investigación del Data Warehouse Institute**: Tendencias y benchmarks de la industria
- **Investigación Gartner**: Magic Quadrants para Plataformas de BI y Analytics

### Conceptos Relacionados
- [Master Data Management](https://en.wikipedia.org/wiki/Master_data_management)
- [Data Lake](https://en.wikipedia.org/wiki/Data_lake) (enfoque complementario)
- [Data Mart](https://en.wikipedia.org/wiki/Data_mart) (subconjunto departamental)
- [Data Governance](https://en.wikipedia.org/wiki/Data_governance)
- [Calidad de Datos](https://es.wikipedia.org/wiki/Calidad_de_datos)

---

## Glosario de Términos Clave

**Change Data Capture (CDC)**: El proceso de identificar y rastrear cambios en los datos fuente

**Dimensión**: Una categoría de información que proporciona contexto (quién, qué, cuándo, dónde, por qué)

**Hecho**: Una medición o métrica sobre un evento de negocio (cuánto, cuántos)

**Hash**: Una huella digital única calculada a partir de datos para detectar cambios

**Idempotente**: Una operación que produce el mismo resultado sin importar cuántas veces se ejecute

**Metodología Kimball**: Un enfoque ampliamente utilizado para diseñar data warehouses basado en modelado dimensional

**Landing Zone**: La primera capa donde los datos crudos llegan desde los sistemas fuente

**OLAP (Online Analytical Processing)**: Tecnología para analizar datos a través de múltiples dimensiones

**Eliminación Suave**: Marcar registros como eliminados sin removerlos físicamente

**Esquema en Estrella**: Un patrón de diseño con hechos en el centro y dimensiones en los bordes

**Clave Sustituta**: Un identificador artificial asignado por el data warehouse

**Seguimiento Temporal**: Registrar cuándo los datos llegaron y cambiaron a lo largo del tiempo

---

**Versión del Documento**: 1.0  
**Última Actualización**: 20 de mayo de 2026  
**Audiencia**: Usuarios Empresariales, Gerentes, Partes Interesadas No Técnicas  
**Metodología**: Modelado Dimensional Kimball
