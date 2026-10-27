# Diagrama y Flujo de Información: PKGLN_DIRECTORIO_PROFESIONALES

## Misión del Paquete
Orquestador Transaccional de Negocio expuesto hacia el Frontend y API Gateway para el Directorio de Profesionales y Motor de Disponibilidad Horaria por Slots y Bitmap.
Gobierna:
- Todas las reglas de negocio y dominio (festivos, ausencias, jerarquía de horarios, cálculo de duración, slots de 5 minutos, vector de 288 bits, conversiones AM/PM).
- Control de transacciones (`p_do_commit` exclusivo, `ROLLBACK`).
- Telemetría centralizada con `uti_manejo_trazas_pkg`.
- Registro de excepciones en `tkr_errores` con `uti_ge_excepciones_pkg.p_grabar_log` (CERO `RAISE_APPLICATION_ERROR`).

---

## Método: p_consultar_directorio

### 1. Descripción en Lenguaje Natural
Orquesta la consulta paginada del directorio de profesionales de la salud habilitados en la plataforma, permitiendo aplicar múltiples filtros combinados (especialidad, convenio, aseguramiento, modalidad y búsqueda por texto):
- Valida los parámetros del payload JSON de entrada y establece valores predeterminados para la paginación (12 médicos por página).
- Evalúa las reglas de auditoría y telemetría iniciando la traza si se encuentra configurada en el sistema.
- Delega en el paquete multi-tabla `pkgcn_directorio_profesionales.p_consultar_profesionales_json` la consulta con paginación server-side.
- Registra el cierre exitoso de la telemetría y entrega la respuesta estructurada con los metadatos de paginación y el catálogo de profesionales.
- En caso de excepción inesperada, efectúa reversión, registra el log forense en `tkr_errores` y emite el mensaje descriptivo en el JSON de salida.

### 2. Decisiones y Bifurcaciones Lógicas
- **Paso 01 [Evaluación de Trazabilidad]**: Si el servicio tiene telemetría activa en las reglas de auditoría; Registra el inicio de traza y vuelve al flujo principal (`uti_manejo_trazas_pkg.f_debe_trazar`)
- **Paso 02 [Apertura de Traza Técnica]**: Si la telemetría se encuentra habilitada; Apertura el registro de seguimiento en la bitácora de auditoría y vuelve al flujo principal (`uti_manejo_trazas_pkg.p_iniciar_traza`)
- **Paso 03 [Consulta Paginada Multi-Tabla]**: Extrae los profesionales habilitados aplicando filtros de rol, estado, franjas y texto con paginación nativa; `pkgcn_directorio_profesionales.p_consultar_profesionales_json`
- **Paso 04 [Telemetría Exitosa]**: Si la traza se encuentra activa; Registra el cierre exitoso de la ejecución en la auditoría y vuelve al flujo principal (`uti_manejo_trazas_pkg.p_finalizar_traza`)
- **Paso 05 [Control Forense de Excepciones]**: Ante cualquier fallo imprevisto; Registra el estado de error en telemetría (`uti_manejo_trazas_pkg.p_finalizar_traza_error`), persiste el volcado forense en la bitácora de incidentes (`uti_ge_excepciones_pkg.p_grabar_log`) y retorna error

### 3. Mapa de Objetos Invocados y Llamados
| Orden | Nombre Exacto del Objeto Invocado | Capa / Familia | Tipo | Propósito de la Invocación | Condición / Momento |
| :---: | :--- | :--- | :--- | :--- | :--- |
| 1 | `uti_manejo_trazas_pkg.f_debe_trazar` | `uti_` | Función | Comprobar si el método tiene telemetría configurada | Al inicio de la ejecución |
| 2 | `uti_manejo_trazas_pkg.p_iniciar_traza` | `uti_` | Procedimiento | Registrar apertura en tkr_traza_ejecucion | Si f_debe_trazar = TRUE |
| 3 | `pkgcn_directorio_profesionales.p_consultar_profesionales_json` | `pkgcn_` | Procedimiento | Ejecutar consulta multi-tabla paginada de profesionales | En flujo principal |
| 4 | `uti_manejo_trazas_pkg.p_finalizar_traza` | `uti_` | Procedimiento | Registrar fin exitoso de la telemetría | Al completar la consulta sin fallos |
| 5 | `uti_manejo_trazas_pkg.p_finalizar_traza_error` | `uti_` | Procedimiento | Registrar fin con estado ERROR en telemetría | Bloque WHEN OTHERS ante fallos |
| 6 | `uti_ge_excepciones_pkg.p_grabar_log` | `uti_` | Procedimiento | Persistir registro técnico del error en tkr_errores | Bloque WHEN OTHERS ante fallos |

---

## Método: p_consultar_disponibilidad

### 1. Descripción en Lenguaje Natural
Orquesta y ejecuta el motor de cálculo de disponibilidad horaria y slots para un profesional asistencial en una fecha puntual (`tipo_vista = 'DIA'`), una semana (`tipo_vista = 'SEMANA'`) o un rango de fechas de hasta 365 días (`tipo_vista = 'RANGO'`).
Aplica en el orquestador:
- Consulta de ausencias médicas programadas (`pkgca_tkr_ausencias_profesional.f_existe_ausencia`).
- Consulta de festivos nacionales y domingos (`pkgca_tkr_festivos.f_es_festivo` y `pkgca_tkr_usuarios.f_trabaja_festivos`).
- Consulta de duración de atención en `pkgca_tkr_tiempos_atencion.f_obtener_duracion_cita`.
- Consulta multi-tabla de turnos vía cursor en `pkgcn_directorio_profesionales.f_consultar_turnos`.
- Jerarquía de vigencias: `POR_DIA` > `PERSONALIZADO` > `BASE`.
- Consulta y descuento de citas reservadas en `tkr_disponibilidad_bitmap`.
- Generación de slots en memoria y construcción del vector binario de 288 bits.

### 2. Decisiones y Bifurcaciones Lógicas
- **Paso 01 [Validación de Entrada]**: Si el payload es nulo o carece de `id_usuario`; Retorna error estructurado (-20001 / -20002).
- **Paso 02 [Bifurcación Vista Rango]**: Si `tipo_vista = 'RANGO'`; Itera día a día (hasta 365 días), calcula disponibilidad y agrega los días con turnos disponibles en el arreglo `dias_disponibles`.
- **Paso 03 [Bifurcación Vista Semanal]**: Si `tipo_vista = 'SEMANA'`; Itera 7 días consecutivos calculando disponibilidad y los agrupa en el arreglo `semana`.
- **Paso 04 [Vista Diaria Estándar]**: Si `tipo_vista = 'DIA'` o por defecto; Calcula y retorna los slots y el bitmap de 288 bits de la fecha indicada.
- **Paso 05 [Control de Excepciones]**: Ante fallos en la consulta; Registra en `tkr_errores` y retorna error estructurado.

### 3. Mapa de Objetos Invocados y Llamados
| Orden | Nombre Exacto del Objeto Invocado | Capa / Familia | Tipo | Propósito de la Invocación | Condición / Momento |
| :---: | :--- | :--- | :--- | :--- | :--- |
| 1 | `pkgca_tkr_tiempos_atencion.f_obtener_duracion_cita` | `pkgca_` | Función | Obtener duración en minutos según aseguramiento y modalidad | Por cada día evaluado |
| 2 | `pkgca_tkr_ausencias_profesional.f_existe_ausencia` | `pkgca_` | Función | Verificar si el profesional tiene ausencia programada | Por cada día evaluado |
| 3 | `pkgca_tkr_festivos.f_es_festivo` | `pkgca_` | Función | Determinar si la fecha es festivo | Por cada día evaluado |
| 4 | `pkgca_tkr_usuarios.f_trabaja_festivos` | `pkgca_` | Función | Verificar si el profesional labora en festivos/domingos | Por cada día evaluado |
| 5 | `pkgcn_directorio_profesionales.f_consultar_turnos` | `pkgcn_` | Función | Consultar cursor multi-tabla de turnos del día de la semana | Por cada día laborable |
| 6 | `uti_manejo_trazas_pkg.p_finalizar_traza` | `uti_` | Procedimiento | Finalizar registro de telemetría | Al finalizar exitosamente |
| 7 | `uti_ge_excepciones_pkg.p_grabar_log` | `uti_` | Procedimiento | Registrar log de excepción en tkr_errores | Bloque WHEN OTHERS |

---

## Método: p_consultar_filtros

### 1. Descripción en Lenguaje Natural
Orquesta la recuperación de catálogos maestros delegando la consulta multi-tabla a `pkgcn_directorio_profesionales.p_consultar_filtros_catalogo_json` con gobierno de excepciones y telemetría.

### 2. Mapa de Objetos Invocados y Llamados
| Orden | Nombre Exacto del Objeto Invocado | Capa / Familia | Tipo | Propósito de la Invocación | Condición / Momento |
| :---: | :--- | :--- | :--- | :--- | :--- |
| 1 | `pkgcn_directorio_profesionales.p_consultar_filtros_catalogo_json` | `pkgcn_` | Procedimiento | Extraer catálogos multi-tabla de especialidades, convenios y aseguramientos | Flujo principal |
| 2 | `uti_ge_excepciones_pkg.p_grabar_log` | `uti_` | Procedimiento | Persistir registro técnico de error si ocurre excepción | Bloque WHEN OTHERS |

---

## Método: p_consultar_intervalos_dia

### 1. Descripción en Lenguaje Natural
Endpoint expuesto para consumo de selectores horarios rápidos que requieren únicamente la lista de intervalos disponibles de un día en formato legible de 12 horas AM/PM:
- Extrae parámetros del JSON (`id_usuario`, `fecha`, `tipo_aseguramiento`, `clase_atencion`, `id_convenio`).
- Aplica las reglas de negocio de mapeo:
  - `tipo_aseguramiento`: `'O'` $\rightarrow 2$ (Obligatorio), otro valor $\rightarrow 1$ (Voluntario).
  - `clase_atencion`: `'D'` $\rightarrow$ Domiciliaria, otro valor $\rightarrow$ Virtual (`'V'`).
- Ejecuta el motor interno de disponibilidad para resolver los slots disponibles.
- Formatea cada slot a formato 12 horas con indicador AM/PM (`HH:MI AM`).
- Retorna un arreglo JSON plano: `[{"INTERVALO":"08:20 PM"},{"INTERVALO":"08:40 PM"},...]`.

---

## Método: p_consultar_intervalos_rango

### 1. Descripción en Lenguaje Natural
Endpoint expuesto para consultar los intervalos disponibles a lo largo de un rango de fechas (hasta 365 días):
- Admite formato de fechas `YYYY-MM-DD` o `DD/MM/YYYY`.
- Aplica reglas de mapeo de aseguramiento y modalidad.
- Itera día por día ejecutando el motor de disponibilidad.
- Retorna un arreglo con cada fecha en formato `DD/MM/YYYY` y su lista de intervalos disponibles:
  `[{"fecha":"27/10/2026","intervalos":[{"INTERVALO":"08:20 PM"},...]},...]`.

---

## Método: p_actualizar_slots_cita

### 1. Descripción en Lenguaje Natural
Orquesta la reserva (`tipo_operacion = 'M'`) o liberación (`tipo_operacion = 'D'`) de slots de cita en el vector de 288 bits:
- Extrae los parámetros obligatorios (`id_profesional` / `id_usuario`, `fecha_hora`).
- Si no se especifica `duracion_minutos`, la calcula automáticamente invocando `pkgca_tkr_tiempos_atencion.f_obtener_duracion_cita`.
- Convierte la hora de inicio y fin a minutos del día y calcula el rango de bits dentro del vector de 288 posiciones (slots de 5 minutos).
- Invoca la operación DML mono-tabla `pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado`.
- Realiza la confirmación atómica controlada mediante **`p_do_commit('pkgln_directorio_profesionales.p_actualizar_slots_cita')`**.
- En caso de error, ejecuta `ROLLBACK;`, registra en `tkr_errores` y retorna mensaje estructurado.

---

## Método: p_marcar_desmarcar_slots

### 1. Descripción en Lenguaje Natural
Orquesta el marcado o desmarcado explícito de slots pasando parámetros discretos de hora y duración:
- Valida los parámetros del payload JSON.
- Calcula las posiciones en el vector de 288 bits.
- Invoca la operación DML mono-tabla en `pkgca_tkr_disponibilidad_bitmap`.
- Ejecuta **`p_do_commit('pkgln_directorio_profesionales.p_marcar_desmarcar_slots')`**.
- Control transaccional atómico con `ROLLBACK;` ante incidentes.

---

## Método: p_consultar_detalle_profesional

### 1. Descripción en Lenguaje Natural
Orquesta la recuperación de la información detallada de un profesional médico al ser seleccionado en el directorio para presentar su ficha técnica o perfil:
- Extrae y valida el identificador del profesional (`id_usuario` o `id`) recibido en `p_json_entrada`.
- Inicia y gestiona la telemetría institucional vía `uti_manejo_trazas_pkg`.
- Delega en `pkgcn_directorio_profesionales.p_consultar_detalle_profesional` la extracción multi-tabla de datos básicos, calificaciones, número de reseñas, especialidades, subespecialidades y enlaces de fotografía.
- Gobierna excepciones imprevistas persistiendo en `tkr_errores` y retornando estructura JSON sin `RAISE_APPLICATION_ERROR`.

### 2. Mapa de Objetos Invocados y Llamados
| Orden | Nombre Exacto del Objeto Invocado | Capa / Familia | Tipo | Propósito de la Invocación | Condición / Momento |
| :---: | :--- | :--- | :--- | :--- | :--- |
| 1 | `uti_manejo_trazas_pkg.f_debe_trazar` | `uti_` | Función | Comprobar si el método tiene telemetría configurada | Al inicio |
| 2 | `uti_manejo_trazas_pkg.p_iniciar_traza` | `uti_` | Procedimiento | Registrar apertura en tkr_traza_ejecucion | Si f_debe_trazar = TRUE |
| 3 | `pkgcn_directorio_profesionales.p_consultar_detalle_profesional` | `pkgcn_` | Procedimiento | Consulta multi-tabla del perfil detallado | Flujo principal |
| 4 | `uti_manejo_trazas_pkg.p_finalizar_traza` | `uti_` | Procedimiento | Registrar cierre de telemetría | Al finalizar con éxito |
| 5 | `uti_ge_excepciones_pkg.p_grabar_log` | `uti_` | Procedimiento | Registrar log de excepción en tkr_errores | Bloque WHEN OTHERS |
