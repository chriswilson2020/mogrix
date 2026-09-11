/*
 * Basic POSIX spawn compatibility for IRIX.
 *
 * The tracked Mogrix spawn.h documents the historical compatibility layer as
 * fork+exec based and only providing basic spawn functionality.  Keep that
 * contract explicit: NULL/empty file-actions and zero-valued attributes are
 * supported; unsupported requested behaviour returns ENOTSUP instead of being
 * silently ignored.
 */

#include <spawn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

static int actions_supported(const posix_spawn_file_actions_t *fa)
{
    return fa == 0 || fa->count == 0;
}

static int attrs_supported(const posix_spawnattr_t *attr)
{
    return attr == 0 || attr->flags == 0;
}

static int spawn_exec(pid_t *pid, const char *path,
                      const posix_spawn_file_actions_t *file_actions,
                      const posix_spawnattr_t *attrp,
                      char *const argv[], char *const envp[])
{
    int errpipe[2];
    pid_t child;
    int child_errno = 0;
    int flags;
    ssize_t got;

    if (!pid || !path || !argv)
        return EINVAL;
    if (!actions_supported(file_actions) || !attrs_supported(attrp))
        return ENOTSUP;

    if (pipe(errpipe) < 0)
        return errno;

    flags = fcntl(errpipe[1], F_GETFD, 0);
    if (flags >= 0)
        (void)fcntl(errpipe[1], F_SETFD, flags | FD_CLOEXEC);

    child = fork();
    if (child < 0) {
        child_errno = errno;
        close(errpipe[0]);
        close(errpipe[1]);
        return child_errno;
    }

    if (child == 0) {
        close(errpipe[0]);
        execve(path, argv, envp ? envp : environ);
        child_errno = errno;
        (void)write(errpipe[1], &child_errno, sizeof(child_errno));
        _exit(127);
    }

    close(errpipe[1]);
    got = read(errpipe[0], &child_errno, sizeof(child_errno));
    close(errpipe[0]);

    if (got == (ssize_t)sizeof(child_errno))
        return child_errno;

    *pid = child;
    return 0;
}

static const char *env_path(char *const envp[])
{
    char *const *p;
    if (envp) {
        for (p = envp; *p; ++p) {
            if (strncmp(*p, "PATH=", 5) == 0)
                return *p + 5;
        }
    }
    return getenv("PATH");
}

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp,
                char *const argv[], char *const envp[])
{
    return spawn_exec(pid, path, file_actions, attrp, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp,
                 char *const argv[], char *const envp[])
{
    const char *path;
    const char *start;
    const char *end;
    char candidate[1024];
    size_t dirlen;
    size_t filelen;
    int rc;
    int last_error = ENOENT;

    if (!file || !*file)
        return ENOENT;

    if (strchr(file, '/'))
        return spawn_exec(pid, file, file_actions, attrp, argv, envp);

    if (!actions_supported(file_actions) || !attrs_supported(attrp))
        return ENOTSUP;

    path = env_path(envp);
    if (!path || !*path)
        path = "/bin:/usr/bin";

    filelen = strlen(file);
    start = path;
    for (;;) {
        end = strchr(start, ':');
        dirlen = end ? (size_t)(end - start) : strlen(start);

        if (dirlen == 0) {
            if (filelen + 1 < sizeof(candidate)) {
                memcpy(candidate, file, filelen + 1);
            } else {
                return ENAMETOOLONG;
            }
        } else {
            if (dirlen + 1 + filelen + 1 > sizeof(candidate))
                return ENAMETOOLONG;
            memcpy(candidate, start, dirlen);
            candidate[dirlen] = '/';
            memcpy(candidate + dirlen + 1, file, filelen + 1);
        }

        rc = spawn_exec(pid, candidate, file_actions, attrp, argv, envp);
        if (rc == 0)
            return 0;
        if (rc != ENOENT && rc != ENOTDIR && rc != EACCES)
            return rc;
        if (rc == EACCES)
            last_error = EACCES;

        if (!end)
            break;
        start = end + 1;
    }

    return last_error;
}

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *fa)
{
    if (!fa)
        return EINVAL;
    memset(fa, 0, sizeof(*fa));
    return 0;
}

int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *fa)
{
    if (!fa)
        return EINVAL;
    fa->count = 0;
    return 0;
}

int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *fa, int fd)
{
    if (!fa || fd < 0)
        return EINVAL;
    if (fa->count >= _MOGRIX_SPAWN_MAX_ACTIONS)
        return ENOMEM;
    fa->actions[fa->count].type = _MOGRIX_SPAWN_ACTION_CLOSE;
    fa->actions[fa->count].fd = fd;
    fa->actions[fa->count].newfd = -1;
    ++fa->count;
    return 0;
}

int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *fa, int fd, int newfd)
{
    if (!fa || fd < 0 || newfd < 0)
        return EINVAL;
    if (fa->count >= _MOGRIX_SPAWN_MAX_ACTIONS)
        return ENOMEM;
    fa->actions[fa->count].type = _MOGRIX_SPAWN_ACTION_DUP2;
    fa->actions[fa->count].fd = fd;
    fa->actions[fa->count].newfd = newfd;
    ++fa->count;
    return 0;
}

int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *fa,
                                     int fd, const char *path,
                                     int oflag, mode_t mode)
{
    (void)fa;
    (void)fd;
    (void)path;
    (void)oflag;
    (void)mode;
    return ENOTSUP;
}

int posix_spawnattr_init(posix_spawnattr_t *attr)
{
    if (!attr)
        return EINVAL;
    memset(attr, 0, sizeof(*attr));
    return 0;
}

int posix_spawnattr_destroy(posix_spawnattr_t *attr)
{
    if (!attr)
        return EINVAL;
    memset(attr, 0, sizeof(*attr));
    return 0;
}

int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags)
{
    if (!attr)
        return EINVAL;
    attr->flags = flags;
    return 0;
}

int posix_spawnattr_getflags(const posix_spawnattr_t *attr, short *flags)
{
    if (!attr || !flags)
        return EINVAL;
    *flags = attr->flags;
    return 0;
}

int posix_spawnattr_setsigmask(posix_spawnattr_t *attr, const sigset_t *mask)
{
    if (!attr || !mask)
        return EINVAL;
    attr->sigmask = *mask;
    attr->flags |= POSIX_SPAWN_SETSIGMASK;
    return 0;
}

int posix_spawnattr_getsigmask(const posix_spawnattr_t *attr, sigset_t *mask)
{
    if (!attr || !mask)
        return EINVAL;
    *mask = attr->sigmask;
    return 0;
}

int posix_spawnattr_setsigdefault(posix_spawnattr_t *attr, const sigset_t *set)
{
    if (!attr || !set)
        return EINVAL;
    attr->sigdefault = *set;
    attr->flags |= POSIX_SPAWN_SETSIGDEF;
    return 0;
}

int posix_spawnattr_setpgroup(posix_spawnattr_t *attr, pid_t pgroup)
{
    if (!attr)
        return EINVAL;
    attr->pgroup = pgroup;
    attr->flags |= POSIX_SPAWN_SETPGROUP;
    return 0;
}
