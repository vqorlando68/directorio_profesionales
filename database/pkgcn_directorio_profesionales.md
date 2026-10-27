# Documentación Funcional: PKGCN_DIRECTORIO_PROFESIONALES

## 1. Misión del Paquete
Capa de Consultas Relacionales Multi-Tabla y DML Multi-Tabla para el Directorio de Profesionales de la Salud y Turnos de Atención.
Encapsula las consultas multi-tabla con sintaxis relacional tradicional Oracle `(+)` y paginación del servidor.
**Regla Institucional de la Capa:** Todos los métodos de `pkgcn_` reciben como parámetro de entrada un payload JSON denominado obligatoriamente `p_json_entrada` y evalúan sus filtros directamente dentro de las sentencias DML/SQL utilizando la función `JSON_VALUE`. No contiene lógica de negocio ni control de transacciones (ambas responsabilidades delegadas en `pkgln_directorio_profesionales`).

---

## Método: p_consultar_profesionales_json

### 1. Descripción Funcional en Lenguaje Natural
Consulta el directorio de profesionales de la salud que se encuentran plenamente habilitados para atender en la plataforma, recibiendo el payload `p_json_entrada`, soportando paginación del lado del servidor y evaluando los filtros combinados directamente en el SQL mediante `JSON_VALUE`.

### 2. Información que Trae (Lectura / Consultas)
- **Parámetro de Entrada:** `p_json_entrada IN CLOB` (contiene `id_especialidad`, `id_convenio`, `id_tipo_aseguramiento`, `modalidad`, `busqueda`, `pagina`, `registros_pagina`).
- **Tablas Consultadas:** `tkr_usuarios` (`u`), `tkr_roles_usuario` (`ru`), `tkr_horarios_profesional` (`h`), `tkr_especialidades_usuario` (`ue`), `tkr_especialidades` (`e`), `tkr_franjas_profesional` (`f`).
- **Filtros Evaluados en SQL con `JSON_VALUE`:**
  - Estado activo (`u.id_estado_usuario = 1`).
  - Rol profesional asistencial: `u.id_rol = 4` o existencia en `tkr_roles_usuario` con `id_rol = 4`.
  - Habilitación de atención: al menos una franja horaria activa en `tkr_horarios_profesional` (`activo = 1`).
  - Especialidad: `ue.id_especialidad = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_especialidad'))`.
  - Convenio: `h.id_convenio = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio'))`.
  - Tipo de aseguramiento: `h.id_tipo_aseguramiento = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento'))`.
  - Modalidad: `f.modalidad = UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.modalidad')))`.
  - Búsqueda textual: `LIKE '%' || UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.busqueda'))) || '%'`.
  - Paginación server-side mediante `OFFSET ... FETCH NEXT ... ROWS ONLY` calculada con `JSON_VALUE(p_json_entrada, '$.registros_pagina')` y `JSON_VALUE(p_json_entrada, '$.pagina')`.
- **Datos Retornados:** Parámetro `p_json_salida` con total de registros, total de páginas, página actual y la lista de profesionales (`profesionales`) donde cada registro cuenta con la estructura estándar e idéntica de `p_consultar_detalle_profesional`: `id`, `fullName`, `trabaja_festivos`, `slug`, `gender`, `rate`, `reviews`, `specialty`, `esp_subesp`, `subspecialty`, `img_url`, `specialtiesIds`, `modalidades`, `correo` y `telefono`.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (procedimiento de solo lectura relacional).

---

## Método: f_consultar_turnos

### 1. Descripción Funcional en Lenguaje Natural
Ejecuta la consulta relacional multi-tabla de los turnos y franjas horarias programadas para un profesional en un día específico de la semana. Recibe `p_json_entrada IN CLOB`, evalúa los filtros con `JSON_VALUE` en la cláusula `WHERE` del cursor y aplica ordenamiento preferente por convenio. Retorna un cursor abierto (`SYS_REFCURSOR`) para ser consumido por el orquestador de negocio `pkgln_`.

### 2. Información que Trae (Lectura / Consultas)
- **Parámetro de Entrada:** `p_json_entrada IN CLOB` (contiene `id_usuario`, `dia_semana`, `id_convenio`, `id_tipo_aseguramiento`).
- **Tablas Consultadas:** `tkr_horarios_profesional` (`h`).
- **Filtros Evaluados en SQL con `JSON_VALUE`:**
  - Identificador de usuario del profesional: `h.id_usuario = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'))`.
  - Día canónico de la semana: `h.dia_semana = JSON_VALUE(p_json_entrada, '$.dia_semana')`.
  - Registro de horario activo: `h.activo = 1`.
  - Filtro opcional por convenio: `h.id_convenio = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio'))`.
  - Filtro opcional por tipo de aseguramiento: `h.id_tipo_aseguramiento = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento'))`.
- **Campos del Cursor:** `id`, `hora_desde`, `hora_hasta`, `id_convenio`, `id_tipo_aseguramiento`, `fecha_inicial`, `fecha_final`.
- **Orden:** Prioridad del convenio consultado (`CASE WHEN h.id_convenio = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio')) THEN 1 ELSE 2 END`), seguido por orden cronológico de `hora_desde`.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (función de solo lectura relacional).

---

## Método: p_consultar_filtros_catalogo_json

### 1. Descripción Funcional en Lenguaje Natural
Recupera los catálogos maestros necesarios para alimentar los selectores de búsqueda del directorio asistencial.

### 2. Información que Trae (Lectura / Consultas)
- **Parámetro de Entrada:** `p_json_entrada IN CLOB DEFAULT NULL`.
- **Tablas Consultadas:** `tkr_especialidades`, `tkr_convenios` (`estado = 'A'`), `tkr_tipos_aseguramiento`.
- **Datos Retornados:** Parámetro `p_json_salida` con arreglos JSON de especialidades, convenios, tipos de aseguramiento y modalidades de atención disponibles.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (procedimiento de solo lectura relacional).

---

## Método: p_consultar_detalle_profesional

### 1. Descripción Funcional en Lenguaje Natural
Consulta la información de perfil y ficha técnica detallada de un profesional médico específico al ser seleccionado en el directorio. Recibe `p_json_entrada IN CLOB` y evalúa el identificador mediante `TO_NUMBER(NVL(JSON_VALUE(p_json_entrada, '$.id_usuario'), JSON_VALUE(p_json_entrada, '$.id')))`.

### 2. Información que Trae (Lectura / Consultas)
- **Parámetro de Entrada:** `p_json_entrada IN CLOB` (contiene `id_usuario` o `id`).
- **Tablas Consultadas:** `tkr_usuarios` (`u`), `tkr_encuesta_paciente` (`ep`), `tkr_citas` (`ct`), `tkr_cita_usuarios` (`cu`), `tkr_especialidades_usuario` (`eu`/`eud`), `tkr_especialidades` (`e`), `tkr_subespecialidad_usu` (`sue`).
- **Filtros Evaluados en SQL con `JSON_VALUE`:**
  - `u.id = TO_NUMBER(NVL(JSON_VALUE(p_json_entrada, '$.id_usuario'), JSON_VALUE(p_json_entrada, '$.id')))`.
- **Funciones Utilitarias / Acceso Invocadas:** `f_nombre_subespecialidades_usuario`, `f_archivo_foto`, `pkgca_tkr_parametros.f_consulta_valor`, `pkgcn_perfil_profesional.f_ids_especialidades_usuario`.
- **Datos Retornados:** Payload JSON con estructura completa: `id`, `fullName`, `trabaja_festivos`, `slug`, `gender`, `rate`, `reviews`, `specialty`, `esp_subesp`, `subspecialty`, `days_of_service`, `img_url`, `specialtiesIds`.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (procedimiento de solo lectura relacional).

---

## Método: f_dias_servicio_profesional

### 1. Descripción Funcional en Lenguaje Natural
Calcula y concatena ordenadamente los días canónicos de la semana (`'LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO'`) en los cuales el profesional tiene turnos de atención configurados y activos en la tabla `tkr_horarios_profesional` para el rango de fechas consultado (`p_fecha_inicio` a `p_fecha_fin`). El cálculo se basa exclusivamente en los horarios programados del profesional, independientemente de si los intervalos de cita se encuentran libres u ocupados en el bitmap.

### 2. Información que Trae (Lectura / Consultas)
- **Parámetros de Entrada:**
  - `p_id_usuario IN NUMBER`: Identificador del usuario profesional.
  - `p_fecha_inicio IN VARCHAR2 DEFAULT NULL`: Fecha inicial del rango de consulta (formato `YYYY-MM-DD` o `DD/MM/YYYY`, por defecto fecha actual).
  - `p_fecha_fin IN VARCHAR2 DEFAULT NULL`: Fecha final del rango de consulta (por defecto `p_fecha_inicio + 6`).
  - `p_id_convenio IN NUMBER DEFAULT NULL`: Filtro opcional por convenio.
  - `p_id_aseg IN NUMBER DEFAULT NULL`: Filtro opcional por tipo de aseguramiento.
- **Tablas Consultadas:** `tkr_horarios_profesional` (`h`).
- **Lógica de Evaluación:**
  - Verifica vigencias de horarios (`fecha_inicial` y `fecha_final`).
  - Si el rango es menor a 7 días, valida mediante generador de calendario en memoria que el día de la semana específico coincida con alguna fecha calendario del rango.
  - Agrupa y ordena los días de la semana de forma canónica (Lunes a Domingo).
- **Datos Retornados:** Cadena de texto formateada con los días separados por coma (e.g., `'LU, MA, MI'`). Si no registra horarios en el rango, retorna `NULL`.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (función determinística de solo lectura relacional).
