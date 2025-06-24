<%@ WebHandler Language="C#" Class="SearchHandler" %>

using System;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using Serilog;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using MarvalSoftware.UI.WebUI.ServiceDesk.RFP.Plugins;

/// <summary>
/// ApiHandler
/// </summary>
public class SearchHandler : PluginHandler
{
    private string BaseUrl
    {
        get
        {
            return this.GlobalSettings["@@JIRABaseUrl"];
        }
    }   
    private string openprojectworkspacename
    {
        get
        {
            return this.GlobalSettings["@@OpenProjectWorkspaceName"];
        }
    }
private string GraphApiBaseUrl
    {
        get
        {
            return "https://graph.openproject.com/";
        }
    }
     private string openprojectapikey
    {
        get
        {
            return this.GlobalSettings["@@OpenProjectAPIKey"];
        }
    }

    private string ApiBaseUrl
    {
        get
        {
            return this.BaseUrl + "rest/api/latest/";
        }
    }

    private string Username
    {
        get
        {
            return this.GlobalSettings["@@JIRAUsername"];
        }
    }

    private string Password
    {
        get
        {
            return this.GlobalSettings["@@JIRAPassword"];
        }
    }

    private string JiraCredentials
    {
        get
        {
            return SearchHandler.GetEncodedCredentials(string.Format("{0}:{1}", this.Username, this.Password));
        }
    }

    private string SearchText { get; set; }
    private int MaximumNumberOfResults { get; set; }

    /// <summary>
    /// Handle Request
    /// </summary>
    public override void HandleRequest(HttpContext context)
    {
        this.ProcessParameters(context.Request);
        string requestSearchResponse = GetOpenProjectProjects(this.SearchText);
        context.Response.Write(requestSearchResponse);
        
    }

    public override bool IsReusable
    {
        get { return false; }
    }

    /// <summary>
    /// Get Paramaters from QueryString
    /// </summary>
    private void ProcessParameters(HttpRequest httpRequest)
    {
        this.SearchText = HttpUtility.UrlDecode(httpRequest.Params["searchText"]) ?? string.Empty;
        Log.Information("Searching for " + this.SearchText);
        int maxResults;
        int.TryParse(httpRequest.Params["maxResults"] ?? string.Empty, out maxResults);
        this.MaximumNumberOfResults = maxResults;
    }
   private string GetOpenProjectProjects(string searchString)
    {
        var NewSearchString = '"' + searchString + '"';
        var queryString = "{ projects(input:{where:{OR:[{title:{LIKE: " + NewSearchString + " }},{number: {LIKE: " + NewSearchString + " }}]}}){ id title description status startdate duedate number completedate clientcontact { firstname lastname } tasks { id name startdate duedate completedate } tags { id name } }}";
        queryString = queryString.Replace("\\\"", "\"");
        dynamic jobject = JObject.FromObject(new
        {
           query = queryString
        });
        Log.Information("Using graph URL of  " + this.GraphApiBaseUrl);
        Log.Information("Have object as " + jobject.ToString());
        var httpWebRequest = SearchHandler.BuildRequest(this.GraphApiBaseUrl, jobject.ToString(), "POST" );
        var response = this.ProcessRequest(httpWebRequest, this.openprojectapikey);
        Log.Information("Have response from search request as " + response);
       
        return response;
        
    }
    /// <summary>
    /// Builds a HttpWebRequest
    /// </summary>
    /// <param name="uri">The uri for request</param>
    /// <param name="body">The body for the request</param>
    /// <param name="method">The verb for the request</param>
    /// <returns>The HttpWebRequest ready to be processed</returns>
    private static HttpWebRequest BuildRequest(string uri = null, string body = null, string method = "GET")
    {
        var request = WebRequest.Create(new UriBuilder(uri).Uri) as HttpWebRequest;
        request.Method = method.ToUpperInvariant();
        request.ContentType = "application/json";

        if (body == null) return request;
        using (var writer = new StreamWriter(request.GetRequestStream()))
        {
            writer.Write(body);
        }

        return request;
    }

    /// <summary>
    /// Proccess a HttpWebRequest
    /// </summary>
    /// <param name="request">The HttpWebRequest</param>
    /// <param name="credentials">The Credentails to use for the API</param>
    /// <returns>Process Response</returns>
    private string ProcessRequest(HttpWebRequest request, string credentials)
    {
        var issueList = new List<object>();

        try
        {
            request.Headers.Add("Authorization", credentials);

            HttpWebResponse response = request.GetResponse() as HttpWebResponse;
            using (StreamReader reader = new StreamReader(response.GetResponseStream()))
            {
                var searchResponse = JsonHelper.FromJson(reader.ReadToEnd());
                var foundIssues = (JArray)searchResponse.data.projects;

                foreach (dynamic issue in foundIssues)
                {
                    Log.Information("Issue details are " + issue.ToString());
                    var issueType = issue.status;
                    var issueSummary = "     " + issue.title;
                    var URL =  "https://app.openproject.com/" + this.openprojectworkspacename + "/?fuseaction=jobs&fusesubaction=jobdetails&Jobs_currentJobID=" + issue.id;
                    issueList.Add(new
                    {
                        Url = URL,
                        Text = string.Format("     {0} ",  issueSummary),
                        PreviewUrl =  string.Format("{0}handler/ApiHandler.ashx?action=ViewSummary&issueUrl={1}", this.PluginBaseUrl, HttpUtility.UrlEncode(Convert.ToString(issue.id))),
                        IconName = "Marval Projects",
                        ExternalIconUrl = string.Format("{0}img/openproject_16.png", this.PluginBaseUrl)
                    });
                }
            }
        }
        catch (WebException ex)
        {
            if (ex.Response == null) return ex.Message;
            using (StreamReader reader = new StreamReader(ex.Response.GetResponseStream()))
            {
                return reader.ReadToEnd();
            }

        }

        return JsonHelper.ToJson(issueList);
    }

    /// <summary>
    /// Encodes Credentials
    /// </summary>
    /// <param name="credentials">The string to encode</param>
    /// <returns>base64 encoded string</returns>
    private static string GetEncodedCredentials(string credentials)
    {
        var byteCredentials = Encoding.UTF8.GetBytes(credentials);
        return Convert.ToBase64String(byteCredentials);
    }

    /// <summary>
    /// JsonHelper Functions
    /// </summary>
    internal class JsonHelper
    {
        public static string ToJson(object obj)
        {
            return JsonConvert.SerializeObject(obj);
        }

        public static dynamic FromJson(string json)
        {
            return JObject.Parse(json);
        }
    }
}