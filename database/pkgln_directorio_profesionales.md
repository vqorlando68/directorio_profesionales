# Diagrama y Flujo de Información: PKGLN_DIRECTORIO_PROFESIONALES

## Método: p_consultar_directorio

### 1. Descripción en Lenguaje Natural
Orquesta la consulta paginada del directorio de profesionales de la salud habilitados en la plataforma, permitiendo aplicar múltiples filtros combinados (especialidad, convenio, aseguramiento, modalidad y búsqueda por texto):
- Valida los parámetros del payload JSON de entrada y establece valores predeterminados para la paginación (12 médicos por página).
- Evalúa las reglas de auditoría y telemetría iniciando la traza si se encuentra configurada en el sistema.
- Delega en el caso de negocio `pkgcn_directorio_profesionales.p_consultar_profesionales_json` la consulta con paginación server-side.
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

```json
// JSON ENTRADA
{
  "id_usuario_ejecutor": 105,
  "id_especialidad": 3,
  "id_convenio": null,
  "id_tipo_aseguramiento": 1,
  "modalidad": "V",
  "busqueda": "carlos",
  "pagina": 1,
  "registros_por_pagina": 12
}
```

```json
// JSON SALIDA
{
  "codigo": 0,
  "mensaje": "Directorio consultado exitosamente",
  "total_registros": 48,
  "total_paginas": 4,
  "pagina_actual": 1,
  "registros_pagina": 12,
  "profesionales": [
    {
      "id_usuario": 47,
      "nombre_completo": "Carlos Andrés Mendoza",
      "nombres": "Carlos Andrés",
      "apellidos": "Mendoza",
      "correo": "cmendoza@teker.com",
      "telefono": "3001234567",
      "trabaja_festivos": "S",
      "url_foto": "/uploads/fotos/47.jpg",
      "especialidades": [
        { "id": 3, "nombre": "Medicina General" }
      ],
      "modalidades": ["V", "D"]
    }
  ]
}
```

---

## Método: p_consultar_disponibilidad

### 1. Descripción en Lenguaje Natural
Consulta la disponibilidad horaria y los slots libres de un profesional médico para una fecha o semana seleccionada, respetando la jerarquía de turnos (Horario por Día > Personalizado > Base), descuentos por ausencias o festivos, y generando el vector de bitmap de 288 bits:
- Extrae y valida el identificador del profesional y la fecha solicitada en formato ISO `YYYY-MM-DD`.
- Invoca la lógica de negocio diaria o semanal según el parámetro `tipo_vista` ('DIA' o 'SEMANA').
- Retorna los intervalos de atención con hora de inicio, hora de fin y el bitmap binario.

### 2. Decisiones y Bifurcaciones Lógicas
- **Paso 01 [Validación de Entrada]**: Si el payload es nulo o no incluye `id_usuario`; Salida inmediata con código -20001 o -20002 por datos obligatorios faltantes
- **Paso 02 [Bifurcación Vista Semanal]**: Si `tipo_vista = 'SEMANA'`; Ejecuta la consulta acumulada de 7 días consecutivos (`pkgcn_directorio_profesionales.p_consultar_slots_semana_json`) y retorna
- **Paso 03 [Vista Diaria Estándar]**: Si `tipo_vista = 'DIA'` o por defecto; Resuelve la disponibilidad puntual del día (`pkgcn_directorio_profesionales.p_consultar_slots_dia_json`) y retorna
- **Paso 04 [Control de Excepciones]**: Ante fallos en la consulta; Retorna código de error estructurado en el JSON de salida

### 3. Mapa de Objetos Invocados y Llamados
| Orden | Nombre Exacto del Objeto Invocado | Capa / Familia | Tipo | Propósito de la Invocación | Condición / Momento |
| :---: | :--- | :--- | :--- | :--- | :--- |
| 1 | `pkgcn_directorio_profesionales.p_consultar_slots_semana_json` | `pkgcn_` | Procedimiento | Resolver disponibilidad para 7 días | Bifurcación: Si tipo_vista = 'SEMANA' |
| 2 | `pkgcn_directorio_profesionales.p_consultar_slots_dia_json` | `pkgcn_` | Procedimiento | Resolver disponibilidad y slots del día | Flujo estándar si tipo_vista = 'DIA' |

```json
// JSON ENTRADA
{
  "id_usuario": 47,
  "fecha": "2026-11-15",
  "tipo_vista": "DIA",
  "id_convenio": null,
  "id_tipo_aseguramiento": 1,
  "modalidad": "V"
}
```

```json
// JSON SALIDA
{
  "codigo": 0,
  "mensaje": "Disponibilidad recuperada exitosamente",
  "id_usuario": 47,
  "fecha": "2026-11-15",
  "dia_semana": "DO",
  "tipo_horario_aplica": "POR_DIA",
  "duracion_cita_min": 20,
  "total_slots": 12,
  "bitmap_disponible": "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "slots": [
    {
      "hora_inicio": "08:00",
      "hora_fin": "08:20",
      "duracion_minutos": 20,
      "disponible": 1
    },
    {
      "hora_inicio": "08:20",
      "hora_fin": "08:40",
      "duracion_minutos": 20,
      "disponible": 1
    }
  ]
}
```

---

## Método: p_consultar_filtros

### 1. Descripción en Lenguaje Natural
Consulta los catálogos maestros requeridos por el frontend para alimentar los filtros de búsqueda (listado de especialidades, convenios activos y tipos de aseguramiento).

### 2. Decisiones y Bifurcaciones Lógicas
- **Paso 01 [Extracción de Catálogos]**: Recupera los catálogos en una sola llamada delegando a `pkgcn_directorio_profesionales.p_consultar_filtros_catalogo_json`.

### 3. Mapa de Objetos Invocados y Llamados
| Orden | Nombre Exacto del Objeto Invocado | Capa / Familia | Tipo | Propósito de la Invocación | Condición / Momento |
| :---: | :--- | :--- | :--- | :--- | :--- |
| 1 | `pkgcn_directorio_profesionales.p_consultar_filtros_catalogo_json` | `pkgcn_` | Procedimiento | Extraer catálogos de especialidades, convenios y aseguramientos | Al inicio |

---

## Método: p_actualizar_slots_cita

### 1. Descripción en Lenguaje Natural
Orquestador de negocio para la reserva (marcado con `'1'`) o liberación (desmarcado con `'0'`) de los slots de cita en el vector bitmap de disponibilidad (`tkr_disponibilidad_bitmap.bitmap_ocupado`) de un profesional de la salud. Recibe la fecha y hora de la cita, calcula la posición de inicio y fin en el vector de 288 bits (bloques discretos de 5 minutos), delega la actualización física a la capa DML mono-tabla `pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado`, gobierna la transacción atómica con `p_do_commit` y gestiona la telemetría centralizada con `uti_manejo_trazas_pkg`.

### 2. Decisiones y Bifurcaciones Lógicas
- **Decisión 1 [Validación Payload]**: Si el payload `p_json_entrada` es nulo; Salida inmediata con código -20001
- **Decisión 2 [Validación Datos Obligatorios]**: Si `id_usuario` o `fecha_hora` son nulos; Salida inmediata con código -20002
- **Decisión 3 [Validación Operación]**: Si `tipo_operacion` no es `'M'` (Marcar) ni `'D'` (Desmarcar); Salida inmediata con código -20003
- **Decisión 4 [Interpretación Fecha/Hora]**: Si el formato de `fecha_hora` es inválido; Salida inmediata con código -20004
- **Paso 05 [Cálculo de Bits]**: Convierte la hora de inicio y duración a minutos desde medianoche y calcula los índices del vector: `idx_inicio = TRUNC(min_inicio / 5) + 1` e `idx_fin = TRUNC(min_fin / 5)`.
- **Paso 06 [Invocación DML Mono-Tabla]**: Construye el payload JSON y llama a `pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado`.
- **Paso 07 [Confirmación Transaccional]**: Ejecuta `p_do_commit('pkgln_directorio_profesionales.p_actualizar_slots_cita')`.

### 3. Mapa de Objetos Invocados y Llamados
| Orden | Nombre Exacto del Objeto Invocado | Capa / Familia | Tipo | Propósito de la Invocación | Condición / Momento |
| :---: | :--- | :--- | :--- | :--- | :--- |
| 1 | `uti_manejo_trazas_pkg.f_debe_trazar` | `uti_` | Función | Evaluar si la operación tiene telemetría activa en `tkr_traza_config` | Al inicio |
| 2 | `uti_manejo_trazas_pkg.p_iniciar_traza` | `uti_` | Procedimiento | Registrar inicio autónomo de la traza de ejecución | Si traza activa = TRUE |
| 3 | `pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado` | `pkgca_` | Procedimiento | Actualizar el campo `bitmap_ocupado` en `tkr_disponibilidad_bitmap` enviando JSON CLOB | Tras calcular índices |
| 4 | `p_do_commit` | `core` | Procedimiento | Confirmación atómica y controlada de la transacción | Tras DML exitoso |
| 5 | `uti_manejo_trazas_pkg.p_finalizar_traza` | `uti_` | Procedimiento | Cerrar traza con estado EXITO | Al finalizar |
| 6 | `uti_ge_excepciones_pkg.p_grabar_log` | `uti_` | Procedimiento | Registro forense del error en `tkr_errores` | En bloque WHEN OTHERS |
| 7 | `uti_manejo_trazas_pkg.p_finalizar_traza_error` | `uti_` | Procedimiento | Cerrar traza con estado ERROR y SQLCODE | En bloque WHEN OTHERS |

### 4. Documentación de Parámetros de Entrada (`p_json_entrada` CLOB)

| Campo | Tipo | Obligatorio | Valor por Defecto | Descripción y Reglas de Negocio |
| :--- | :---: | :---: | :---: | :--- |
| `id_usuario` | NUMBER | **SÍ** | N/A | Identificador del profesional médico (`tkr_usuarios.id`). |
| `fecha_hora` | VARCHAR2 | **SÍ** | N/A | Fecha y hora de inicio del intervalo a marcar en formato `YYYY-MM-DD HH24:MI` o ISO `YYYY-MM-DD"T"HH24:MI:SS` (ej. `'2026-10-27 08:20'`). |
| `duracion_minutos` | NUMBER | NO | `20` | Duración del procedimiento o cita en minutos. Define la amplitud del rango de slots a marcar (ej. `20`, `40`, `60` min). |
| `tipo_operacion` | VARCHAR2 | **SÍ** | N/A | **`'M'`** para **Marcar como Ocupado** (escribe `'1'` en los bits correspondientes).<br>**`'D'`** para **Desmarcar / Liberar** (escribe `'0'` en los bits para liberar el cupo por cancelación). |
| `id_tipo_aseguramiento` | NUMBER | NO | `1` | `1` = Voluntario (Prepagada/Póliza), `2` = Obligatorio (EPS). |
| `clase_atencion` / `modalidad` | VARCHAR2 | NO | `'V'` | `'V'` = Virtual / Telemedicina, `'D'` = Atención Domiciliaria. |
| `id_convenio` | NUMBER | NO | `NULL` | ID del convenio si la cita aplica a un convenio específico. `NULL` actualiza las franjas generales del profesional. |

---

### 5. Cálculo Matemático del Rango de Bits en el Vector (288 posiciones)

El vector binario `bitmap_ocupado` representa las 24 horas del día divididas en **288 intervalos de 5 minutos** (1440 min / 5 = 288 bits):
1. **Minutos desde medianoche:**  
   $$\text{min\_inicio} = (\text{hora} \times 60) + \text{minuto}$$  
   $$\text{min\_fin} = \text{min\_inicio} + \text{duracion\_minutos}$$
2. **Índice inicial y final en el vector (1-based):**  
   $$\text{idx\_inicio} = \text{TRUNC}(\text{min\_inicio} / 5) + 1$$  
   $$\text{idx\_fin} = \text{TRUNC}(\text{min\_fin} / 5)$$

> [!TIP]
> **Ejemplo de Rango de Slots (Cita de 40 minutos de 08:20 a 09:00):**
> - Hora de inicio: `08:20` $\rightarrow 8 \times 60 + 20 = 500$ minutos.
> - Duración: `40` minutos $\rightarrow$ Minuto fin: $500 + 40 = 540$ minutos.
> - $\text{idx\_inicio} = \text{TRUNC}(500 / 5) + 1 = 101$.
> - $\text{idx\_fin} = \text{TRUNC}(540 / 5) = 108$.
> - **Acción:** Los bits desde la posición **101 hasta la 108** (8 bits consecutivos de 5 min) se actualizan a `'1'`, marcando 40 minutos continuos como ocupados.

---

### 6. Esquemas y Payloads JSON de Ejemplo

#### Ejemplo A: Marcar Rango como Ocupado al Crear o Agendar Cita (`tipo_operacion = 'M'`)

**JSON Entrada (`p_json_entrada`):**
```json
{
  "id_usuario": 65,
  "fecha_hora": "2026-10-27 08:20",
  "duracion_minutos": 40,
  "tipo_operacion": "M",
  "id_tipo_aseguramiento": 1,
  "modalidad": "V",
  "id_convenio": null
}
```

**JSON Salida Exitoso (`p_json_salida`):**
```json
{
  "codigo": 0,
  "mensaje": "Slots de cita reservados/marcados exitosamente",
  "id_usuario": 65,
  "fecha": "2026-10-27",
  "hora_inicio": "08:20",
  "duracion_minutos": 40,
  "idx_inicio": 101,
  "idx_fin": 108,
  "tipo_operacion": "M",
  "filas_afectadas": 1
}
```

#### Ejemplo B: Liberar / Desmarcar Rango por Cancelación de Cita (`tipo_operacion = 'D'`)

**JSON Entrada (`p_json_entrada`):**
```json
{
  "id_usuario": 65,
  "fecha_hora": "2026-10-27 08:20",
  "duracion_minutos": 40,
  "tipo_operacion": "D",
  "id_tipo_aseguramiento": 1,
  "modalidad": "V"
}
```

**JSON Salida Exitoso (`p_json_salida`):**
```json
{
  "codigo": 0,
  "mensaje": "Slots de cita liberados/desmarcados exitosamente",
  "id_usuario": 65,
  "fecha": "2026-10-27",
  "hora_inicio": "08:20",
  "duracion_minutos": 40,
  "idx_inicio": 101,
  "idx_fin": 108,
  "tipo_operacion": "D",
  "filas_afectadas": 1
}
```

---

### 7. Script del Bloque Anónimo PL/SQL de Prueba

Script listo para ejecutar en Toad, Oracle SQL Developer o PL/SQL Developer para marcar un rango de slots como ocupados:

```sql
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- 1. Payload de entrada para MARCAR (ocupar) una cita de 40 min de 08:20 a 09:00
    v_json_entrada CLOB := '{
        "id_usuario": 65,
        "fecha_hora": "2026-10-27 08:20",
        "duracion_minutos": 40,
        "tipo_operacion": "M",
        "id_tipo_aseguramiento": 1,
        "modalidad": "V",
        "id_convenio": null
    }';
    
    v_json_salida CLOB;
BEGIN
    -- 2. Invocación del orquestador transaccional PKGLN
    pkgln_directorio_profesionales.p_actualizar_slots_cita(
        p_json_entrada => v_json_entrada,
        p_json_salida  => v_json_salida
    );

    -- 3. Visualizar resultado con los índices de bits actualizados
    DBMS_OUTPUT.PUT_LINE('====================================================');
    DBMS_OUTPUT.PUT_LINE('RESPUESTA ACTUALIZACIÓN DE SLOTS COMO OCUPADOS:');
    DBMS_OUTPUT.PUT_LINE('====================================================');
    DBMS_OUTPUT.PUT_LINE(SUBSTR(v_json_salida, 1, 4000));
END;
/
```


