# Documentación Funcional: PKGCA_TKR_TIEMPOS_ATENCION

## 1. Misión del Paquete
Capa de Acceso No-PK y operaciones mono-tabla exclusiva sobre la tabla `TKR_TIEMPOS_ATENCION`. Encapsula la obtención de la duración en minutos de las citas médicas según el tipo de aseguramiento (Voluntario / Obligatorio) y la modalidad de atención (Virtual o Domiciliaria), recibiendo payloads estructurados en formato JSON y evaluados con `JSON_VALUE`, aplicando las reglas de fallback institucional (20 minutos por defecto).

---

## Método: f_obtener_duracion_cita

### 1. Descripción Funcional en Lenguaje Natural
Consulta la duración en minutos configurada para las atenciones de un profesional de la salud. Recibe un JSON de entrada y extrae con `JSON_VALUE`:
- `id_usuario`: ID del profesional evaluado.
- `id_tipo_aseguramiento`: 1 = Voluntario, 2 = Obligatorio.
- `modalidad`: `'V'` (Virtual) o `'D'` (Domiciliaria).

Evalúa si la atención corresponde a modalidad Domiciliaria (`'D'`) para aplicar el campo específico `duracion_domiciliaria` o la modalidad Virtual/estándar (`'V'`) para tomar el campo `duracion`. Si el médico no tiene parametrizada una duración para el aseguramiento solicitado o si ocurre una excepción, retorna el valor predeterminado de 20 minutos.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_tiempos_atencion` (`ta`).
- **Filtros Aplicados:** `ta.id_usuario = v_id_usuario AND ta.id_tipo_aseguramiento = v_id_tipo_aseguramiento AND ta.activo = 1`.
- **Datos Retornados:** `NUMBER` con los minutos de duración calculados (`duracion_domiciliaria` si `modalidad = 'D'` y no es nulo; de lo contrario `NVL(duracion, 20)`).

```json
{
  "id_usuario": 65,
  "id_tipo_aseguramiento": 1,
  "modalidad": "V"
}
```

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML.

---

## Método: f_consultar_x_profesional

### 1. Descripción Funcional en Lenguaje Natural
Obtiene el listado completo de configuraciones de tiempos de atención activas asociadas a un profesional médico para todos sus tipos de aseguramiento parametrizados, recibiendo el identificador del usuario encapsulado en un payload JSON y evaluado con `JSON_VALUE(p_json_entrada, '$.id_usuario')`.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_tiempos_atencion` (`ta`).
- **Filtros Aplicados:** `ta.id_usuario = v_id_usuario AND ta.activo = 1`.
- **Datos Retornados:** `SYS_REFCURSOR` conteniendo las columnas: `id`, `id_usuario`, `id_tipo_aseguramiento`, `duracion`, `duracion_domiciliaria`, `activo`.

```json
{
  "id_usuario": 65
}
```

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML.
