# Documentación Funcional: PKGCN_DIRECTORIO_PROFESIONALES

## 1. Misión del Paquete
Capa de Casos de Negocio Multi-Tabla para el Directorio de Profesionales de la Salud y Motor de Cálculo de Disponibilidad. Encapsula las consultas de profesionales habilitados con paginación nativa y el algoritmo de cálculo de slots e intervalos con jerarquía estricta de horarios y vector de bitmap.

---

## Método: p_consultar_profesionales_json

### 1. Descripción Funcional en Lenguaje Natural
Consulta el directorio de profesionales de la salud que se encuentran plenamente habilitados para atender en la plataforma, soportando paginación del lado del servidor y filtros combinados.

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
- No realiza operaciones DML (procedimiento de solo lectura).

---

## Método: p_consultar_slots_dia_json

### 1. Descripción Funcional en Lenguaje Natural
Calcula los intervalos de atención (slots) y genera el vector de bitmap binario de 288 bits para un médico en una fecha específica, aplicando estrictamente la jerarquía de turnos y las exclusiones por ausencias o restricciones dominicales/festivas.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_horarios_profesional` (`h`), `tkr_tiempos_atencion` (`ta`), `tkr_ausencias_profesional` (`a`), `tkr_festivos` (`f`), `tkr_usuarios` (`u`).
- **Filtros y Jerarquía:**
  - Comprueba si el día está bloqueado por ausencia programada en `tkr_ausencias_profesional`.
  - Si es festivo o domingo, verifica `trabaja_festivos`.
  - Evalúa y aplica el turno según la jerarquía estricta:
    1. **Nivel 1:** Horario por Día (`fecha_inicial = fecha_final = fecha`).
    2. **Nivel 2:** Horario Personalizado (`fecha_inicial <= fecha AND fecha_final >= fecha`).
    3. **Nivel 3:** Horario Base permanente (`fecha_inicial <= fecha AND fecha_final IS NULL`).
  - Consulta la duración de consulta en `tkr_tiempos_atencion` según el tipo de aseguramiento y la modalidad requerida.
- **Datos Retornados:** Parámetro `p_json_salida` con fecha, día de la semana, tipo de horario aplicado, duración de cita en minutos, arreglo de slots (`hora_inicio`, `hora_fin`, `disponible`) y el vector `bitmap_disponible` de 288 caracteres binarios.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML.

---

## Método: p_consultar_slots_semana_json

### 1. Descripción Funcional en Lenguaje Natural
Itera y calcula la disponibilidad horaria y los slots libres de un profesional para una semana completa (7 días consecutivos a partir de una fecha de inicio).

### 2. Información que Trae (Lectura / Consultas)
- Invoca internamente `p_consultar_slots_dia_json` para cada uno de los 7 días consecutivos.
- **Datos Retornados:** Parámetro `p_json_salida` con el arreglo de los 7 días y sus respectivos slots y bitmaps.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML.

---

## Método: p_consultar_filtros_catalogo_json

### 1. Descripción Funcional en Lenguaje Natural
Recupera los catálogos maestros necesarios para alimentar los selectores de búsqueda del directorio.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_especialidades`, `tkr_convenios` (`estado = 'A'`), `tkr_tipos_aseguramiento`.
- **Datos Retornados:** Parámetro `p_json_salida` con arreglos de especialidades, convenios, tipos de aseguramiento y modalidades de atención disponibles.

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML.

---

## Método: p_consultar_intervalos_dia_json

### 1. Descripción Funcional en Lenguaje Natural
Consulta de alta eficiencia y mínima latencia diseñada para alimentar selectores de citas o interfaces de usuario que requieren únicamente las horas de inicio de los intervalos o slots de atención disponibles para un médico en una fecha determinada. Los horarios se retornan formateados en formato de 12 horas con indicador AM/PM.

### 2. Documentación de Entrada (`p_json_entrada` CLOB)

#### Parámetros del Payload JSON:
| Campo | Tipo | Obligatorio | Valor por Defecto | Valores Permitidos / Descripción |
| :--- | :---: | :---: | :---: | :--- |
| `id_usuario` | NUMBER | **SÍ** | N/A | Identificador del profesional asistencial en `tkr_usuarios`. |
| `fecha` | VARCHAR2 | **SÍ** | N/A | Fecha a consultar en formato ISO `YYYY-MM-DD`. |
| `tipo_aseguramiento` | VARCHAR2 | NO | `'V'` | `(V)`oluntario (id 1) o `(O)`bligatorio (id 2). Si no se pasa, toma `'V'` por defecto. |
| `clase_atencion` | VARCHAR2 | NO | `'V'` | `(V)`irtual o `(D)`omiciliario. Si no se pasa, toma `'V'` por defecto. |
| `id_convenio` | NUMBER | NO | `NULL` | Identificador del convenio específico (`tkr_convenios`). |

#### Ejemplo de JSON de Entrada (`p_json_entrada`):
```json
{
  "id_usuario": 105,
  "fecha": "2026-10-27",
  "tipo_aseguramiento": "V",
  "clase_atencion": "V",
  "id_convenio": null
}
```

---

### 3. Documentación de Salida (`p_json_salida` CLOB)

Retorna un arreglo JSON directo con objetos que contienen la propiedad `INTERVALO` en formato 12 horas `HH:MI AM/PM`:

#### Ejemplo de JSON de Salida (`p_json_salida`):
```json
[
  {
    "INTERVALO": "08:20 PM"
  },
  {
    "INTERVALO": "08:40 PM"
  },
  {
    "INTERVALO": "09:00 PM"
  },
  {
    "INTERVALO": "09:20 PM"
  }
]
```

> [!NOTE]
> Si el profesional no cuenta con disponibilidad en la fecha, o los parámetros son inválidos, el método retorna un arreglo vacío: `[]`.

---

### 4. Información que Modifica (Escritura / DML)
- **Tablas Afectadas:** Ninguna (0 operaciones DML).
- Es un procedimiento de solo lectura y cálculo en memoria de alta velocidad.

---

### 5. Script del Bloque Anónimo PL/SQL de Prueba

Script listo para ejecutar en Toad, Oracle SQL Developer o PL/SQL Developer:

```sql
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- 1. Definición del JSON de Entrada
    v_json_entrada CLOB := '{
        "id_usuario": 105,
        "fecha": "2026-10-27",
        "tipo_aseguramiento": "V",
        "clase_atencion": "V"
    }';
    
    -- 2. Variable para capturar el JSON de Salida
    v_json_salida  CLOB;
BEGIN
    -- 3. Invocación del método optimizado
    pkgcn_directorio_profesionales.p_consultar_intervalos_dia_json(
        p_json_entrada => v_json_entrada,
        p_json_salida  => v_json_salida
    );

    -- 4. Impresión del resultado
    DBMS_OUTPUT.PUT_LINE('--- RESPUESTA INTERVALOS DISPONIBLES ---');
    DBMS_OUTPUT.PUT_LINE(SUBSTR(v_json_salida, 1, 32000));
END;
/
```

---

## Método: p_consultar_intervalos_rango_json

### 1. Descripción Funcional en Lenguaje Natural
Consulta de alta eficiencia que evalúa la disponibilidad de un profesional de la salud en un **rango de fechas**. Retorna la lista de días ordenados cronológicamente con la fecha formateada en `dd/mm/yyyy` y, dentro de cada día, el listado de intervalos o slots libres formateados en reloj de 12 horas con indicador AM/PM.

### 2. Documentación de Entrada (`p_json_entrada` CLOB)

#### Parámetros del Payload JSON:
| Campo | Tipo | Obligatorio | Valor por Defecto | Valores Permitidos / Descripción |
| :--- | :---: | :---: | :---: | :--- |
| `id_usuario` | NUMBER | **SÍ** | N/A | Identificador del profesional asistencial en `tkr_usuarios`. |
| `fecha_inicio` | VARCHAR2 | **SÍ** | N/A | Fecha inicial del rango. Admite formatos `YYYY-MM-DD` o `DD/MM/YYYY`. (También acepta `fecha` como alias). |
| `fecha_fin` | VARCHAR2 | NO | `fecha_inicio` | Fecha final del rango. Admite formatos `YYYY-MM-DD` o `DD/MM/YYYY`. Si no se envía, toma `fecha_inicio`. |
| `tipo_aseguramiento` | VARCHAR2 | NO | `'V'` | `(V)`oluntario (id 1) o `(O)`bligatorio (id 2). Si no se pasa, toma `'V'` por defecto. |
| `clase_atencion` | VARCHAR2 | NO | `'V'` | `(V)`irtual o `(D)`omiciliario. Si no se pasa, toma `'V'` por defecto. |
| `id_convenio` | NUMBER | NO | `NULL` | Identificador del convenio específico (`tkr_convenios`). |
| `solo_disponibles` | VARCHAR2 | NO | `'S'` | `'S'` = Retorna solo los días que tienen al menos un intervalo libre. `'N'` = Retorna todos los días del rango (los días sin cupos tendrán `intervalos: []`). |

#### Ejemplo de JSON de Entrada (`p_json_entrada`):
```json
{
  "id_usuario": 105,
  "fecha_inicio": "2026-10-27",
  "fecha_fin": "2026-10-31",
  "tipo_aseguramiento": "V",
  "clase_atencion": "V",
  "id_convenio": null,
  "solo_disponibles": "S"
}
```

---

### 3. Documentación de Salida (`p_json_salida` CLOB)

Retorna un arreglo JSON donde cada elemento representa un día del rango con formato `dd/mm/yyyy` y su arreglo de intervalos libres:

#### Ejemplo de JSON de Salida (`p_json_salida`):
```json
[
  {
    "fecha": "27/10/2026",
    "intervalos": [
      {
        "INTERVALO": "08:20 PM"
      },
      {
        "INTERVALO": "08:40 PM"
      },
      {
        "INTERVALO": "09:00 PM"
      },
      {
        "INTERVALO": "09:20 PM"
      }
    ]
  },
  {
    "fecha": "28/10/2026",
    "intervalos": [
      {
        "INTERVALO": "08:00 AM"
      },
      {
        "INTERVALO": "08:30 AM"
      }
    ]
  }
]
```

---

### 4. Información que Modifica (Escritura / DML)
- **Tablas Afectadas:** Ninguna (0 operaciones DML).
- Proceso de solo lectura y cálculo analítico en memoria.

---

### 5. Script del Bloque Anónimo PL/SQL de Prueba

Script listo para ejecutar en Toad, Oracle SQL Developer o PL/SQL Developer:

```sql
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- 1. JSON de Entrada con rango de fechas y parámetros
    v_json_entrada CLOB := '{
        "id_usuario": 105,
        "fecha_inicio": "27/10/2026",
        "fecha_fin": "31/10/2026",
        "tipo_aseguramiento": "V",
        "clase_atencion": "V",
        "solo_disponibles": "S"
    }';
    
    -- 2. Variable para capturar el JSON de Salida
    v_json_salida  CLOB;
BEGIN
    -- 3. Invocación del método de rango
    pkgcn_directorio_profesionales.p_consultar_intervalos_rango_json(
        p_json_entrada => v_json_entrada,
        p_json_salida  => v_json_salida
    );

    -- 4. Impresión del resultado
    DBMS_OUTPUT.PUT_LINE('--- RESPUESTA INTERVALOS POR RANGO DE FECHAS ---');
    DBMS_OUTPUT.PUT_LINE(SUBSTR(v_json_salida, 1, 32000));
END;
/
```



