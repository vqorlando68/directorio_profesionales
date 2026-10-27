# Documentación Funcional: PKGCN_DIRECTORIO_PROFESIONALES

## 1. Misión del Paquete
Capa de Consultas Relacionales Multi-Tabla y DML Multi-Tabla para el Directorio de Profesionales de la Salud y Turnos de Atención. Encapsula las consultas multi-tabla con sintaxis relacional tradicional Oracle `(+)` y paginación del servidor. No contiene lógica de negocio ni control de transacciones (ambas responsabilidades delegadas en `pkgln_directorio_profesionales`).

---

## Método: p_consultar_profesionales_json

### 1. Descripción Funcional en Lenguaje Natural
Consulta el directorio de profesionales de la salud que se encuentran plenamente habilitados para atender en la plataforma, soportando paginación del lado del servidor y filtros combinados relacionales.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_usuarios` (`u`), `tkr_roles_usuario` (`ru`), `tkr_horarios_profesional` (`h`), `tkr_especialidades_usuario` (`ue`), `tkr_especialidades` (`e`), `tkr_franjas_profesional` (`f`).
- **Filtros Aplicados:**
  - Estado activo (`u.id_estado_usuario = 1`).
  - Rol profesional asistencial: `u.id_rol = 4` o existencia en `tkr_roles_usuario` con `id_rol = 4`.
  - Habilitación de atención: debe contar con al menos una franja horaria activa registrada en `tkr_horarios_profesional` (`activo = 1`).
  - Filtro por especialidad (`p_id_especialidad`).
  - Filtro por convenio admitido (`p_id_convenio`).
  - Filtro por tipo de aseguramiento (`p_id_tipo_aseguramiento`: 1 = Voluntario, 2 = Obligatorio).
  - Filtro por modalidad de atención (`p_modalidad`: 'V' = Virtual, 'D' = Domiciliaria).
  - Búsqueda textual parcial sobre nombres, apellidos o correo electrónico.
  - Paginación server-side mediante `OFFSET ... FETCH NEXT ... ROWS ONLY`.
- **Datos Retornados:** Parámetro `p_json_salida` con total de registros, total de páginas, página actual y la lista de profesionales con sus datos básicos, fotografía, catálogo de especialidades asociadas y modalidades activas.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (procedimiento de solo lectura relacional).

---

## Método: f_consultar_turnos

### 1. Descripción Funcional en Lenguaje Natural
Ejecuta la consulta relacional multi-tabla de los turnos y franjas horarias programadas para un profesional en un día específico de la semana, aplicando ordenamiento preferente por convenio. Retorna un cursor abierto (`SYS_REFCURSOR`) para ser consumido por el orquestador de negocio `pkgln_`.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_horarios_profesional` (`h`).
- **Filtros Aplicados:**
  - Identificador de usuario del profesional (`h.id_usuario = p_id_usuario`).
  - Día canónico de la semana (`h.dia_semana = p_dia_semana`).
  - Registro de horario activo (`h.activo = 1`).
  - Filtro opcional por convenio (`h.id_convenio = p_id_convenio` o turno general sin convenio asignado).
  - Filtro opcional por tipo de aseguramiento (`h.id_tipo_aseguramiento = p_id_tipo_aseguramiento` o general).
- **Campos del Cursor:** `id`, `hora_desde`, `hora_hasta`, `id_convenio`, `id_tipo_aseguramiento`, `fecha_inicial`, `fecha_final`.
- **Orden:** Turnos específicos del convenio consultado primero (`CASE WHEN h.id_convenio = p_id_convenio THEN 1 ELSE 2 END`), seguidos por orden cronológico de `hora_desde`.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (función de solo lectura relacional).

---

## Método: p_consultar_filtros_catalogo_json

### 1. Descripción Funcional en Lenguaje Natural
Recupera los catálogos maestros necesarios para alimentar los selectores de búsqueda del directorio asistencial.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_especialidades`, `tkr_convenios` (`estado = 'A'`), `tkr_tipos_aseguramiento`.
- **Datos Retornados:** Parámetro `p_json_salida` con arreglos JSON de especialidades, convenios, tipos de aseguramiento y modalidades de atención disponibles.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (procedimiento de solo lectura relacional).

---

## Método: p_consultar_detalle_profesional

### 1. Descripción Funcional en Lenguaje Natural
Consulta la información de perfil y ficha técnica detallada de un profesional médico específico al ser seleccionado en el directorio, incluyendo calificación promedio (rate), conteo de reseñas (reviews), especialidades, subespecialidad principal, fotografía, slug y género.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_usuarios` (`u`), `tkr_encuesta_paciente` (`ep`), `tkr_citas` (`ct`), `tkr_cita_usuarios` (`cu`), `tkr_especialidades_usuario` (`eu`/`eud`), `tkr_especialidades` (`e`), `tkr_subespecialidad_usu` (`sue`).
- **Funciones Utilitarias / Acceso Invocadas:** `f_nombre_subespecialidades_usuario`, `f_archivo_foto`, `pkgca_tkr_parametros.f_consulta_valor`, `pkgcn_perfil_profesional.f_ids_especialidades_usuario`.
- **Datos Retornados:** Payload JSON con estructura completa: `id`, `fullName`, `trabaja_festivos`, `slug`, `gender`, `rate`, `reviews`, `specialty`, `esp_subesp`, `subspecialty`, `img_url`, `specialtiesIds`.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML (procedimiento de solo lectura relacional).
