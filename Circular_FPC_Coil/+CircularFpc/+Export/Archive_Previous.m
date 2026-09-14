function archived = Archive_Previous(cfg, currentOutputPath)
%ARCHIVE_PREVIOUS 把同一输出根下、与当前产物同类型的旧正式产物移入 archive/。
%
%   ARCHIVED = ARCHIVE_PREVIOUS(CFG, CURRENTOUTPUTPATH)
%
%   规则（生成一次新产物后自动整理输出根）：
%     - **按类型各自保留最新一份**：类型 = 设计名词干（去掉 auto 命名的
%       `__yyyyMMdd_HHmmss` 时间戳后缀），只归档与当前产物同词干的旧产物；
%       其他类型的产物无论新旧都留在原处；
%     - 只归档“完整产物”目录：含 reports/08_file_manifest.csv 的目录；
%     - 跳过当前产物自身、archive/ 与非目录条目（如 LATEST.txt、临时目录）；
%     - 归档目标已存在时追加 _2、_3…… 后缀，绝不覆盖既有归档；
%     - 单个目录移动失败只告警并跳过，不回滚已成功发布的新产物；
%     - 任何归档/指针写入异常都只告警：新产物已发布成功，整理失败不应让它失败；
%     - 最后把 LATEST.txt 指向当前产物（写临时文件后替换）。
%
%   返回被归档的目录名（cell，按处理顺序）。
archived = {};
try
    archived = archivePreviousImpl(cfg, currentOutputPath);
catch err
    warning('CircularFPC:ArchiveFailed', ...
        'Automatic archiving skipped after publishing %s: %s', ...
        currentOutputPath, err.message);
end
end

function archived = archivePreviousImpl(cfg, currentOutputPath)
archived = {};
if ~isfolder(currentOutputPath)
    return;
end
outputRoot = fileparts(currentOutputPath);
if isempty(outputRoot)
    outputRoot = cfg.outputRoot;
end
archiveRoot = fullfile(outputRoot, 'archive');
if ~isfolder(archiveRoot)
    [created, message] = mkdir(archiveRoot);
    if ~created
        warning('CircularFPC:ArchiveFailed', ...
            'Unable to create the archive folder %s (%s).', archiveRoot, message);
        return;
    end
end

currentStem = artifactStem(cfg.designName);
entries = dir(outputRoot);
for k = 1:numel(entries)
    name = entries(k).name;
    if ~entries(k).isdir || any(strcmp(name, {'.', '..', 'archive'})) || ...
            strcmp(name, cfg.designName)
        continue;
    end
    if ~strcmp(artifactStem(name), currentStem)
        continue;   % 其他类型的产物保持原位（每类各留最新一份）
    end
    sourcePath = fullfile(outputRoot, name);
    if ~isfile(fullfile(sourcePath, 'reports', '08_file_manifest.csv'))
        continue;   % 非完整产物（临时目录、报告目录等）保持原位
    end
    targetPath = uniqueArchiveTarget(archiveRoot, name);
    [moved, message] = movefile(sourcePath, targetPath);
    if ~moved
        warning('CircularFPC:ArchiveFailed', ...
            'Unable to archive %s into %s (%s).', sourcePath, archiveRoot, message);
        continue;
    end
    archived{end + 1} = name; %#ok<AGROW>
    fprintf('ARCHIVED: %s -> archive/%s\n', name, ...
        targetPath(numel(archiveRoot) + 2:end));
end

writeLatestPointer(outputRoot, cfg.designName);
end

function stem = artifactStem(name)
% 设计名词干：去掉 auto 命名的时间戳后缀（`__yyyyMMdd_HHmmss`）。
% 显式命名的产物没有时间戳，词干即名字本身。
stem = regexprep(name, '__\d{8}_\d{6}$', '');
end

function target = uniqueArchiveTarget(archiveRoot, name)
% 目标重名时追加 _2、_3……，绝不覆盖既有归档。
target = fullfile(archiveRoot, name);
suffix = 2;
while isfolder(target) || isfile(target)
    target = fullfile(archiveRoot, sprintf('%s_%d', name, suffix));
    suffix = suffix + 1;
end
end

function writeLatestPointer(outputRoot, designName)
% LATEST.txt 记录当前正式产物目录名；先写 .new 再替换，避免半截文件。
% 任何失败（如文件被占用）只告警：它是指针文件，不应让已发布的产物失败。
latestFile = fullfile(outputRoot, 'LATEST.txt');
try
    pendingFile = [latestFile '.new'];
    fid = fopen(pendingFile, 'w');
    if fid == -1
        warning('CircularFPC:ArchiveFailed', 'Unable to write %s.', pendingFile);
        return;
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', designName);
    clear cleanup;
    if isfile(latestFile)
        delete(latestFile);
    end
    [moved, message] = movefile(pendingFile, latestFile);
    if ~moved
        warning('CircularFPC:ArchiveFailed', ...
            'Unable to update %s (%s).', latestFile, message);
    end
catch err
    warning('CircularFPC:ArchiveFailed', ...
        'Unable to update %s (%s).', latestFile, err.message);
end
end
