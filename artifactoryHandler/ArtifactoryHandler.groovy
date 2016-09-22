package artifactory
/**
 * Created by EXT.Tim.Harris on 31-03-2016.
 */


// TODO Change resolver to wanted Artifactory URL, i.e, http://artifact.mycompany.com:8081/artifactory/repo/

@GrabResolver(name='artifactory', root='http://localhost:8081/artifactory/repo/', m2Compatible=true)
@Grab(group ='org.jfrog.artifactory.client', module ='artifactory-java-client-services', version = '0.16')
@Grab(group='org.jfrog.artifactory.client', module='artifactory-java-client-services', version='0.13')
@Grab(group ='org.jfrog.artifactory.client', module ='artifactory-java-client-ning-services', version = '0.16')
@Grab(group='args4j', module='args4j', version='2.33')
@GrabExclude(group='org.codehaus.groovy', module='groovy-xml')

import org.jfrog.artifactory.client.Artifactory
import org.jfrog.artifactory.client.ArtifactoryClient
import org.jfrog.artifactory.client.Repositories
import org.jfrog.artifactory.client.model.LightweightRepository
import org.jfrog.artifactory.client.model.RepoPath
import org.jfrog.artifactory.client.model.impl.RepositoryTypeImpl
import org.jfrog.artifactory.client.UploadableArtifact
import org.kohsuke.args4j.Argument;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.CmdLineException;
import org.kohsuke.args4j.Option

import java.util.regex.Pattern

class ArtifactHandler {

    Artifactory server;
    List<LightweightRepository> repositories;

    // Always required
    @Option(name='--action', metaVar='action', usage="The action to perform. Either upload, download, find or list-repos, eg --action 'upload'", required=true)
    String action;
    @Option(name='--web-server', metaVar='webServer', usage="URL to use to access Artifactory server, eg --web-server 'http://localhost:8081/'", required=true)
    String webServer;
    @Option(name='--userName', metaVar='userName', usage="userName to use to access Artifactory server, --userName 'admin'", required=true)
    String userName;
    @Option(name='--password', metaVar='password', usage="Password to use to access Artifactory server, eg  --password 'SomePassword'", required=true)
    String password;

    // Required for upload and download
    @Option(name='--artifact', metaVar='artifact', usage="The named artifact to download, eg  --artifact 'Myjar.jar'")
    String artifact;
    @Option(name='--repository', metaVar='repository', usage="The repository where the named artifact exists, eg  --repository 'libs-release-prod'")
    String repository;
    @Option(name='--version', metaVar='version', usage="The version of the named artifact to download, eg --version '1.0.0'")
    String version;
    @Option(name='--domain', metaVar='domain', usage="The path to place the artifact, eg --repository 'libs-snaphsot-local' --domain 'com/dsv/ds/content'")
    String domain;

    // If not set, defaults to scripts directory
    @Option(name='--location', metaVar='location', usage="The location of the artifact to upload, eg --action 'upload' --location '/home/artifacts'")
    String location;

    @Argument
    private List<String> arguments = new ArrayList<String>();

    @SuppressWarnings(["SystemExit", "CatchThrowable"])
    public static void main( String[] args ) {
        try {
            new ArtifactHandler().doMain( args );
        } catch (Throwable throwable) {
            // Java returns exit code 0 if it terminates because of an uncaught Throwable.
            // That's bad if we have a process like Bamboo depending on errors being non-zero.
            // Thus, we catch all Throwables and explicitly set the exit code.
            println( "Unexpected error: ${throwable}" )
            System.exit(1)
        }
        System.exit(0);
    }

    void doMain(String[] args) throws IOException {
        CmdLineParser parser = new CmdLineParser( this );
        try {
            parser.parseArgument(args);
        } catch (CmdLineException e) {
            System.err.println(e.getMessage());
            parser.printUsage(System.err)
            System.exit(1);
        }
        connect();
        checkArguments();
        switch (action) {
            case 'download':
                download();
                break
            case 'upload':
                upload();
                break
            case 'list-repos':
                list_repos();
                break
            case 'find':
                if(artifact != null && domain != null && version != null && repository != null){
                    RepoPath fqdn = findUnambiguous(repository, domain + "/" + version + "/" + artifact, true)
                    if(fqdn == null){
                        println(domain + "/" + version + "/" + artifact + " does not exist on Artifactory!\nExiting with (1)...")
                        System.exit(1);
                    }
                } else {
                    find_abiguous(repository);
                }
                break
            default:
                throw new CmdLineException("You must specify a valid action.\nExiting with (1)...");
        }
        disconnect();
    }

    private download(){
        println("Starting download...")
        RepoPath fqdn = findUnambiguous(repository,domain + '/' + version + '/' + artifact, false);
        if (fqdn != null) {
            println("Downloading " + artifact + " from folder: " + server.repository(repository).folder(domain + "/" + version).info().getName());
            InputStream is = server.repository( fqdn.getRepoKey()).download(fqdn.getItemPath()).doDownload();
            writeFile(is);
        } else {
            println(artifact + " does not exist on Artifactory! Try using 'find' action.\nExiting with (1)...")
            System.exit(1);
        }
    }

    private void upload(){
        println("Starting upload...")
        RepoPath fqdn = findUnambiguous(repository, domain + '/' + version + '/' + artifact, false);
        if(fqdn != null) {
            println("Artifact already exists at: " + fqdn.getItemPath() + " in repository: " + fqdn.getRepoKey() + "\nExiting with (1)...");
            System.exit(1);
        } else {
            File artifactUp = new File(location + '/' + artifact);
            if (artifactUp.exists()) {
                println("Starting Upload of " + artifact + " to repository " + repository + " at " + domain + "/" + version)
                UploadableArtifact uploadHnd = server.repository(repository).upload(domain + '/' + version + '/' + artifact, artifactUp);
                if (uploadHnd != null){
                    def ret = uploadHnd.doUpload();
                    println("Upload Completed on: " + ret.getCreated() + "...")
                } else {
                    println("Could not get an UpLoad Handle!\nExiting with (1)...");
                    System.exit(1);
                }
            } else {
                println("Can't find artifact file: " + artifactUp.toString() + "\nExiting with (1)...")
                System.exit(1);
            }
        }
    }

    private List<RepoPath> find_abiguous(String repo){
        List<RepoPath> repoPath;
        if(repo != null) {
            repoPath = server.searches().repositories(repo) .artifactsByName(artifact).doSearch();
            println("Looking for artifact: " + artifact + " in repository: " + repository);
        } else {
            repoPath = server.searches().artifactsByName(artifact).doSearch();
            println("Looking for artifact: " + artifact + " in ALL repositories.");
        }
        if (repoPath != null && repoPath.size() >= 1) {
            for (path in repoPath) {
                printPath(path);
            }
        }
        return repoPath;
    }

    private RepoPath findUnambiguous(String repo, String fqdn, boolean verbose){
        List<RepoPath> repoPath;
        def ret = null;
        if(repo != null) {
            repoPath = server.searches().repositories(repo).artifactsByName(artifact).doSearch();
            if(repoPath != null && repoPath.size() >= 1) {
                for(path in repoPath) {
                    if(fqdn == path.getItemPath()){
                        ret = path;
                        if(verbose) {
                            printPath(ret);
                        }
                    }
                }
            }
        }
        return ret;
    }

    private void list_repos(){
        println("listing repositories...")
        Repositories repos = server.repositories();
        List repoList = repos.list( RepositoryTypeImpl.LOCAL );
        print_repos(repoList);
        repoList = repos.list( RepositoryTypeImpl.REMOTE );
        print_repos(repoList);
        repoList = repos.list( RepositoryTypeImpl.VIRTUAL );
        print_repos(repoList);
    }

    // Helper functions
    private void checkArguments(){
        println("Checking arguments and values...")
        if ((action == 'download' || action == 'upload') && (artifact == null || repository == null || version == null)){
            println("You must provide an 'artifact', a 'repository' and a 'version'!\nExiting with (1)...");
            System.exit(1);
        }
        if (action == 'find' && artifact == null){
            println("You must provide an 'artifact'!\nExiting with (1)...");
            System.exit(1);
        }
        checkDomain();
        // Set location default
        if (location == null) {
            location = new File(getClass().getProtectionDomain().getCodeSource().getLocation().getPath()).getParent();
        } else {
            location = location.replaceAll('/$', "");
        }
        if(repository != null){
            if(!repoExists(repository)){
                println("Repository does not exist!\nExiting with (1)...");
                System.exit(1);
            }
        }
        checkVersion()
    }

    private boolean checkVersion(){
        if(version != null && !version.matches("(\\d+\\.\\d+\\.\\d+)")){
            println("Version does not match expected pattern!\nExiting with (1)...");
            System.exit(1);
        }
    }

    private boolean checkDomain(){
        //Strip leading and trailing slashes
        if(domain != null){
            if(!domain.matches(".*/(\\d+\\.\\d+\\.\\d+)")){
                domain = domain.replaceAll("^/+", "");
                domain = domain.replaceAll('/$', "");
            } else {
                println("Domain must not end in version. Use --version argument!\nExiting with 1...")
                System.exit(1);
            }
        }
    }

    private void connect(){
        println("Connecting to: " + webServer + "...")
        if(!webServer.matches("http://.*/")){
            println("--webserver 'value' does not conform to required 'http://host/' pattern!\nExiting with (1)...")
            System.exit(1);
        } else {
            try {
                this.server = ArtifactoryClient.create( "${webServer}artifactory", userName, password );
            } catch (Exception e) {
                printException(e);
            }
        }
    }

    private void disconnect(){
        try {
            this.server.close();
        } catch (Exception e) {
            printException(e);
        }
    }

    private void printException(Exception e){
        Pattern p = Pattern.compile(".*:.*:(.*)");
        String error = e.getMessage().find(p);
        println(error);
    }

    private boolean repoExists(String repository){
        boolean ret = false;
        Repositories repos = server.repositories();
        List repoList = repos.list(RepositoryTypeImpl.LOCAL);
        ret = matchRepo(repoList, repository);
        if(!ret){
            repoList = repos.list( RepositoryTypeImpl.REMOTE );
            ret = matchRepo(repoList, repository);
        }
        if(!ret){
            repoList = repos.list( RepositoryTypeImpl.VIRTUAL )
            ret = matchRepo(repoList, repository);
        }
        return ret;
    }

    private boolean matchRepo(List repoList, String match){
        boolean ret = false;
        for(repo in repoList){
            if(repo.key == match){
                ret = true;
            }
        }
        return ret;
    }

    private void print_repos(List repoList) {
        for( it in repoList ) {
            println("-------------------------------------")
            println "key :" + it.key
            println "type : " + it.type
            println "description : " + it.description
            println "url : " + it.url
            println ""
        };
    }

    private void printPath(RepoPath path){
        println("-------------------------------------")
        println("Found in Repository: " + path.getRepoKey() )
        println("Path is: " + path.getItemPath())
        println ""
    }

    private void writeFile(InputStream inputStream) {
        if (inputStream.available()) {
            byte[] buffer = new byte[1024];
            try {
                OutputStream outputStream = new FileOutputStream(artifact)
                try {
                    int bytesRead;
                    while ((bytesRead = inputStream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                    };
                } catch(IOException e) {
                    System.err.println(e.getMessage());
                    System.exit(1);
                } finally {
                    outputStream.close()
                }
            } catch(IOException e) {
                System.err.println(e.getMessage());
                System.exit(1);
            } finally {
                inputStream.close()
            }
        }
        println("Artifact: " + artifact + " downloaded...")
    }
}
