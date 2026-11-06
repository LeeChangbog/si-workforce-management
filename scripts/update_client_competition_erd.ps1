$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$nativePath = Join-Path $repoPath 'docs/erd/SI_통합_ERD.damx'
$auditPath = Join-Path $repoPath 'docs/model/competition-native-audit.json'
$workPath = Join-Path $repoPath 'build/native-competition'
New-Item -ItemType Directory -Path $workPath -Force | Out-Null

# Start DA# normally before this script; dismiss its trial notice if shown.
# This uses DA#'s own COM API, not screen or keyboard automation.
$app = New-Object -ComObject Modeler5.Application
$model = $app.GetActiveModel()
if (-not $model -or $model.GetFilePath() -ne $nativePath) {
    $app.OpenFile($nativePath)
    $model = $app.GetActiveModel()
}
if (-not $model -or $model.GetFilePath() -ne $nativePath) {
    throw 'The repository native model must be active.'
}

function Get-Entities {
    $result = @()
    for ($i = 0; $i -lt $model.Entitys.Count; $i++) {
        $entity = $model.Entitys.Item($i)
        $result += $entity
        for ($j = 0; $j -lt $entity.SubSets.Count; $j++) {
            $subset = $entity.SubSets.Item($j)
            for ($k = 0; $k -lt $subset.SubTypes.Count; $k++) {
                $result += $subset.SubTypes.Item($k)
            }
        }
    }
    return $result
}

function Get-EntitySnapshot($entity) {
    $attributes = @()
    for ($i = 0; $i -lt $entity.Attributes.Count; $i++) {
        $attribute = $entity.Attributes.Item($i)
        $attributes += [ordered]@{
            name = $attribute.Name
            column = $attribute.ColName
            type = $attribute.ColType
            length = $attribute.ColLen
            pk = [bool]$attribute.PK
            fk = [bool]$attribute.FK
            not_null = [bool]$attribute.NotNull
        }
    }
    return [ordered]@{
        name = $entity.Name
        table = $entity.TableName
        description = $entity.Desc
        attributes = @($attributes | Sort-Object { $_.column })
    }
}

function Get-RelationSnapshot($relation) {
    $parentMany = $false; $childMany = $false
    $parentMandatory = $false; $childMandatory = $false
    $relation.GetLineCardinality([ref]$parentMany, [ref]$childMany)
    $relation.GetLineMandatory([ref]$parentMandatory, [ref]$childMandatory)
    $parent = $relation.GetParent()
    $roles = @()
    for ($i = 0; $i -lt $parent.Attributes.Count; $i++) {
        $attribute = $parent.Attributes.Item($i)
        if ($attribute.PK) {
            $roles += [ordered]@{ source = $attribute.Name; target = $relation.GetRoleName($attribute) }
        }
    }
    return [ordered]@{
        name = $relation.Name
        parent = $parent.Name
        child = $relation.GetChild().Name
        roles = $roles
        parent_many = $parentMany
        child_many = $childMany
        parent_mandatory = $parentMandatory
        child_mandatory = $childMandatory
        identifying = [bool]$relation.IdentifierInhert
        child_not_inherit = [bool]$relation.ChildNotInherit
    }
}

function Get-ExistingStructure {
    $entities = @(Get-Entities | Where-Object { $_.Name -ne '발주처경쟁관계' } |
        Sort-Object Name | ForEach-Object { Get-EntitySnapshot $_ })
    $relations = @()
    for ($i = 0; $i -lt $model.Relations.Count; $i++) {
        $relation = $model.Relations.Item($i)
        if ($relation.Name -notin @('경쟁기준', '경쟁상대')) {
            $relations += Get-RelationSnapshot $relation
        }
    }
    return [ordered]@{ entities = $entities; relations = @($relations | Sort-Object { $_.name }) }
}

$before = Get-ExistingStructure
if ($before.entities.Count -ne 25 -or $before.relations.Count -ne 26) {
    throw 'Expected the original 25 tables and 26 ordinary relationships.'
}
$beforeJson = $before | ConvertTo-Json -Depth 15
$beforeJson | Set-Content -LiteralPath (Join-Path $workPath 'before.json') -Encoding utf8
if (-not $model.GetEntity('발주처경쟁관계')) {
    Copy-Item -LiteralPath $nativePath -Destination (Join-Path $workPath 'original.damx') -Force
}

$client = $model.GetEntity('발주처')
$competition = $model.GetEntity('발주처경쟁관계')
if (-not $competition) { $competition = $model.NewEntity('발주처경쟁관계') }
$competition.TableName = 'CLIENT_COMPETITION'
$competition.Desc = '경쟁 관계인 발주처 쌍. 발주처 간 셀프 M:N을 해소하는 교차 엔티티. 한 쌍은 한 방향(A<B)으로만 저장. PostgreSQL. CHECK (CLIENT_ID_A < CLIENT_ID_B); CHECK (RELEASED_ON IS NULL OR RELEASED_ON >= REGISTERED_ON). 해제일 NULL = 현재 유효.'

foreach ($spec in @(
    @('등록일', 'REGISTERED_ON', 'DATE', '', $true),
    @('해제일', 'RELEASED_ON', 'DATE', '', $false),
    @('등록사유', 'REASON', 'VARCHAR', '200', $true)
)) {
    $attribute = $competition.Attributes.FindName($spec[0])
    if (-not $attribute) { $attribute = $competition.NewAttribute($spec[0]) }
    $attribute.ColName = $spec[1]
    $attribute.ColType = $spec[2]
    if ($spec[3]) { $attribute.ColLen = $spec[3] }
    $attribute.NotNull = $spec[4]
}

foreach ($spec in @(
    @('경쟁기준', '기준발주처번호', 'CLIENT_ID_A'),
    @('경쟁상대', '경쟁발주처번호', 'CLIENT_ID_B')
)) {
    $relation = $model.Relations.FindName($spec[0])
    if (-not $relation) {
        $relation = $model.LinkRelationRoleName($client, @('발주처번호'), $competition, @($spec[1]))
        $relation.Name = $spec[0]
        $relation.ParentVerb = $spec[0]
        $relation.SetRoleName($client.Attributes.FindName('발주처번호'), $spec[1])
    }
    $relation.IdentifierInhert = $true
    $relation.ChildNotInherit = $false
    $relation.SetLineCardinality($false, $true)
    $relation.SetLineMandatory($false, $true)
    $attribute = $competition.Attributes.FindName($spec[1])
    if (-not $attribute) { throw "Missing role attribute $($spec[1])" }
    $attribute.ColName = $spec[2]
    # PK/NN come from the identifying relationship. Never mutate parent keys.
    if (-not $attribute.PK -or -not $attribute.FK -or -not $attribute.NotNull) {
        throw "The identifying FK must be PK/FK/NOT NULL: $($spec[1])"
    }
}
$competition.UpdateDrawEntity()

# Keep the original entities and their coordinates. Add the new entity to the
# overview's free space and provide a focused subject for the two role lines.
$overview = $model.GetSubject('00_통합ERD').GetLogicalPane()
$maxRight = 0
for ($i = 0; $i -lt $overview.Entitys.Count; $i++) {
    $entity = $overview.Entitys.Item($i)
    if ($entity.Name -eq '발주처경쟁관계') { continue }
    $x = 0; $y = 0; $width = 0; $height = 0
    $overview.GetObjectPosition($entity, [ref]$x, [ref]$y, [ref]$width, [ref]$height)
    $maxRight = [Math]::Max($maxRight, $x + $width)
}
if (-not $overview.Entitys.FindName('발주처경쟁관계')) {
    $overview.AppendObjectWithPosition($competition, ($maxRight + 35), 88, 0, 0)
    $overview.SizeFitEntity($competition)
}
$focus = $model.GetSubject('04_정보차단벽')
$newFocus = -not $focus
if ($newFocus) { $focus = $model.NewSubject('04_정보차단벽') }
$pane = $focus.GetLogicalPane()
if (-not $pane.Entitys.FindName('발주처')) { $pane.AppendObjectWithPosition($client, 40, 60, 0, 0) }
if (-not $pane.Entitys.FindName('발주처경쟁관계')) { $pane.AppendObjectWithPosition($competition, 210, 60, 0, 0) }
if ($newFocus) {
    $pane.SizeFitEntity($client)
    $pane.SizeFitEntity($competition)
    $pane.AppendTextBox(40, 180, 350, 70, '정보 차단벽 / PostgreSQL / IE. 두 실선 관계: 경쟁기준(CLIENT A), 경쟁상대(CLIENT B). 각각 발주처 1 : 경쟁관계 0..N. 복합 PK(CLIENT_ID_A,CLIENT_ID_B). CHECK CLIENT_ID_A < CLIENT_ID_B. CHECK RELEASED_ON IS NULL OR RELEASED_ON >= REGISTERED_ON. 해제일 NULL=현재 유효.')
    $pane.LayoutRelation()
}

$after = Get-ExistingStructure
if (($after | ConvertTo-Json -Depth 15) -ne $beforeJson) {
    throw 'An original entity or relationship changed. Native file was not saved.'
}
if ($model.Entitys.Count -ne 21 -or $model.Relations.Count -ne 28) {
    throw 'Expected exactly one new root entity and two new ordinary relationships.'
}
$newEntity = Get-EntitySnapshot $competition
if ($newEntity.attributes.Count -ne 5) { throw 'CLIENT_COMPETITION must have exactly five attributes.' }
$newRelations = @('경쟁기준', '경쟁상대') | ForEach-Object {
    Get-RelationSnapshot ($model.Relations.FindName($_))
}
$model.Desc = $model.Desc -replace '20개 루트', '21개 루트' -replace '26개 관계', '28개 관계'
$model.ActionCommit('정보 차단벽: 발주처경쟁관계 1개와 식별 관계 2개 추가')
$app.SaveActiveModelFile()

# Verify the saved file, rather than relying solely on the in-memory model.
$app.CloseActiveModelFile()
$app.OpenFile($nativePath)
$model = $app.GetActiveModel()
if ($model.Entitys.Count -ne 21 -or $model.Relations.Count -ne 28 -or
    ((Get-ExistingStructure | ConvertTo-Json -Depth 15) -ne $beforeJson) -or
    ((Get-EntitySnapshot ($model.GetEntity('발주처경쟁관계')) | ConvertTo-Json -Depth 15) -ne
     ($newEntity | ConvertTo-Json -Depth 15))) {
    throw 'Saved native model failed the reopen verification.'
}
$reopenedRelations = @('경쟁기준', '경쟁상대') | ForEach-Object {
    Get-RelationSnapshot ($model.Relations.FindName($_))
}
if (($reopenedRelations | ConvertTo-Json -Depth 15) -ne ($newRelations | ConvertTo-Json -Depth 15)) {
    throw 'Saved native relationships failed the reopen verification.'
}
$subjectCounts = @(for ($i = 0; $i -lt $model.Subjects.Count; $i++) {
    $subject = $model.Subjects.Item($i)
    $subjectPane = $subject.GetLogicalPane()
    [ordered]@{ subject = $subject.Name; entities = $subjectPane.Entitys.Count; relations = $subjectPane.Relations.Count }
})
$audit = [ordered]@{
    verified_on = '2026-11-06'
    method = 'DA# native COM API; existing entity and relationship snapshots compared before save'
    root_entity_count = $model.Entitys.Count
    subtype_count = 5
    ordinary_relation_count = $model.Relations.Count
    existing_entities_preserved = ($before.entities.Count -eq 25)
    existing_relations_preserved = ($before.relations.Count -eq 26)
    existing_structure_equal_before_after = $true
    saved_file_reopened_verified = $true
    reopened_subject_counts = $subjectCounts
    new_entity = $newEntity
    new_relations = @($newRelations)
    subjects = @(for ($i = 0; $i -lt $model.Subjects.Count; $i++) { $model.Subjects.Item($i).Name })
    check_constraints = @('CLIENT_ID_A < CLIENT_ID_B', 'RELEASED_ON IS NULL OR RELEASED_ON >= REGISTERED_ON')
    checks_storage = 'Native entity description and model metadata; enforced by SQL V1'
    limitations = @('Existing native UNIQUE getter issue is unchanged; see native-audit.md.', 'Native diagram visual layout is not screen-inspected; PNG/SVG/draw.io are the inspected display artifacts.')
}
$audit | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $auditPath -Encoding utf8
$model.ExportJson() | Set-Content -LiteralPath (Join-Path $workPath 'after-export.json') -Encoding utf8
[pscustomobject]@{ saved = $nativePath; roots = $model.Entitys.Count; ordinary_relations = $model.Relations.Count; audit = $auditPath } | ConvertTo-Json
