package artifactory

/**
 * Created by timothy on 4/7/16.
 * Each upload or download test should create an artifact as the first step.
 * You can set the variable verbose to true to get output. But it is a bit messy..
 */
class ArtifactHandlerTest extends GroovyTestCase {
    def base = "groovy ArtifactoryHandler.groovy "
    def command = ""
    def server = " --web-server "
    def userName = " --userName "
    def password = " --password "
    def action = " --action "
    def repository = " --repository "
    def version = " --version "
    def artifact = " --artifact "
    def domain = " --domain "
    def location = " --location "
    def resource = new File(getClass().getProtectionDomain().getCodeSource().getLocation().getPath()).getParent() + "/resources"
    def repo1 = "libs-content-test"
    def repo2 = "libs-content-local"
    boolean verbose = false

    void setUp() {
        super.setUp()
    }

    void tearDown() {
        def scrap = new File("deploy-scripts.tar.gz")
        if (scrap.exists()) {
            scrap.delete()
        }
    }

    void testConnectionServer(){
        println("Test connection: Bad server string.")
        command = base + action + "list-repos" + server + "htp://localhost:8081/" + userName + "admin" + password + "password"
        execute(command, 1)
    }

    void testConnectionHost(){
        println("Test connection: Wrong host.")
        command = base + action + "list-repos" + server + "http://localhost:8080/" + userName + "admin" + password + "password"
        execute(command, 1)
    }

    void testConnectionUser(){
        println("Test connection: Unknown user.")
        command = base + action + "list-repos" + server + "http://localhost:8080/" + userName + "wrong" + password + "password"
        execute(command, 1)
    }

    void testConnectionPassword(){
        println("Test connection: Bad password.")
        command = base + action + "list-repos" + server + "http://localhost:8080/" + userName + "admin" + password + "wrong"
        execute(command, 1)
    }

    void testListRepos() {
        println("Test list-repos.")
        def command = base + action + "list-repos" + server + "http://localhost:8081/" + userName + "admin" + password + "password"
        execute(command, 0)
    }

    void testUploadSuccess() {
        println("Test Upload: Success.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.0" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)
    }

    void testUploadExists(){
        println("Test Upload: Already Exists.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.1" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.1" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,1)
    }

    void testUploadBadRepo(){
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.2" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        println("Test Upload: Repository doesn't exist.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + "wrong" + version + "1.0.2" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,1)
    }

    void testUploadVersion(){
        println("Test Upload: Bad version.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "wrong" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,1)
    }

    void testFindAmbiguous(){
        println("Test Ambiguous find: Success.")
        command = base + action + "find" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts"
        execute(command, 0)
    }

    void testFindUnambiguous(){
        println("Test Unambiguous find: Success.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.3" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "find" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.3" + domain +
                "com/dsv/ds/content"
        execute(command, 0)
    }

    void testFindDomain(){
        println("Test Unambiguous find: Wrong domain.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.4" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "find" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.4" + domain + "com/dsv/wrong/content"
        execute(command, 1)
    }

    void testFindExists(){
        println("Test Unambiguous find: Doesn't exist.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.5" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "find" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "wrong" + repository + repo1 + version + "1.0.5" + domain + "com/dsv/wrong/content"
        execute(command, 1)
    }

    void testFindRepository(){
        println("Test Unambiguous find: Bad repository.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.6" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "find" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + "libs-content-wrong" + version + "1.0.6" + domain + "com/dsv/ds/content"
        execute(command, 1)
    }

    void testFindVersion(){
        println("Test Unambiguous find: Bad version.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.7" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "find" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "wrong" + domain +
                "com/dsv/ds/content"
        execute(command, 1)
    }

    void testDownload()
    {
        println("Test Download: Success.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.8" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "download" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.8" + domain +
                "com/dsv/ds/content"
        execute(command,0)
    }

    void testDownloadVersion(){
        println("Test Download: Version doesn't exist.")
        command = base + action + "download" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "10.0.0" + domain +
                "com/dsv/ds/content"
        execute(command,1)
    }

    void testDownloadArtifact(){
        println("Test Download: Ambiguous artifact name.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.9" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "download" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "wrong" + repository + repo1 + version + "1.0.9" + domain +
                "com/dsv/ds/content"
        execute(command,1)
    }

    void testDownloadRepository(){
        println("Test Download: Artifact exists but NOT in specified repository.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo2 + version + "1.0.10" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "download" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.10" + domain +
                "com/dsv/ds/content"
        execute(command,1)
    }

    void testDownloadDomain(){
        println("Test Download: Not under domain.")
        command = base + action + "upload" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.11" + domain +
                "com/dsv/ds/content" + location + resource
        execute(command,0)

        command = base + action + "download" + server + "http://localhost:8081/" + userName + "admin" + password + "password" +
                artifact + "deploy-scripts.tar.gz" + repository + repo1 + version + "1.0.11" + domain +
                "com/dsv/wrong/content"
        execute(command,1)
    }

    boolean execute(String command, int expected) {
        def ret = 1 // used for download tests to clean up
        def sout = new StringBuffer()
        def serr = new StringBuffer()
        def proc = command.execute()
        proc.waitForProcessOutput(sout, serr)
        if(verbose) {
            println(sout.toString())
        }
        println("------------------------------------")
        println(command)
        println("Expect" + "(" + expected + ")")
        println("Got" + "(" + proc.exitValue() + ")")
        println("")
        if(proc.exitValue() != expected) {
            assert false: "Expected " + expected + " but got " + proc.exitValue() + "\n"
            ret = 0
        }
        return ret
    }
}

